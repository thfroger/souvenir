import SwiftUI
import UIKit
import Foundation
import Security
import CryptoCore

/// Re-encodes an image to JPEG, which drops EXIF/GPS metadata (SECURITY.md §8.1),
/// and bounds its dimensions. A rigorous strip would use ImageIO; UIImage
/// re-encoding is an effective, simple equivalent for the skeleton.
enum ImageTools {
    static func stripExifJPEG(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// The vault key (VK) lives in the Keychain so encrypted memories survive
/// relaunches (SECURITY.md §3). AfterFirstUnlockThisDeviceOnly: not synced, not
/// in backups, available once the device has been unlocked.
enum VaultKeychain {
    private static let account = "vaultKey"

    /// Load the existing VK, or nil if none is retrievable on this device.
    /// **Never creates one.** Minting a fresh VK over already-sealed entries can't
    /// unwrap their DEKs, so it would orphan every existing memory — the "pushed
    /// but invisible" failure observed on device after a signing change. A missing
    /// VK with entries on disk is a "key unavailable" condition the caller must
    /// surface, not paper over (SECURITY.md §7: a lost key is lost access — but the
    /// app must never silently inflict that on itself).
    static func load() -> SymmetricKey? {
        guard let data = SecureStore.load(account), let key = try? SymmetricKey(bytes: [UInt8](data)) else { return nil }
        return key
    }

    /// Mint and persist a brand-new VK. Call **only** when establishing a fresh
    /// vault (no sealed entries exist yet).
    static func create() -> SymmetricKey? {
        guard let key = try? VaultKey.generate() else { return nil }
        SecureStore.save(account, Data(key.bytes))
        return key
    }
}

/// On-device memory store (SECURITY.md §3). Each entry's text content and media
/// blob are encrypted with a per-entry data key (DEK), wrapped under the
/// Keychain-held vault key (VK). Entries persist to disk; the Frise/Arbre read
/// decrypted `Memory` values.
///
/// At rest, the index fields (child/kind/date) are still cleartext — encrypting
/// the index file under the VK is a §6.4 hardening for later. Server upload is
/// the next step.
@MainActor
final class MemoryStore: ObservableObject {
    /// Everything that isn't the media blob is encrypted here — including the
    /// child, the type and the civil date (special category, SECURITY.md §1.4):
    /// the server and the on-disk index see none of it.
    private struct Content: Codable {
        let childID: UUID
        let kind: MemoryKind
        let createdAt: Date
        let title: String
        let note: String?
        let audio: String?
    }

    /// Fully opaque on disk and on the wire: an id + ciphertext + a wrapped key.
    /// No cleartext index remains at rest (closes the §6.4 gap).
    private struct StoredEntry: Codable {
        let id: UUID
        let sealed: AEAD.Sealed       // encrypted Content
        let sealedBlob: AEAD.Sealed?  // encrypted media blob (image or audio), if any
        let wrappedKey: WrappedKey    // per-entry DEK wrapped under the VK
        /// Demo/seed scaffolding: local-only, never pushed to the shared vault.
        /// The samples are deterministic and re-seeded identically on every device,
        /// so syncing them would only pile duplicate, cross-key "unreadable" rows
        /// onto the server. Only genuine captures travel.
        let local: Bool
        /// Plaintexts padded-by-tiers before sealing (SECURITY §6.2). Entries
        /// written before padding existed carry `false` and skip the unpad.
        let padded: Bool

        init(id: UUID, sealed: AEAD.Sealed, sealedBlob: AEAD.Sealed?, wrappedKey: WrappedKey,
             local: Bool = false, padded: Bool = false) {
            self.id = id; self.sealed = sealed; self.sealedBlob = sealedBlob; self.wrappedKey = wrappedKey
            self.local = local; self.padded = padded
        }

        // Back-compatible decode: entries written before `local`/`padded` existed
        // load with those flags false, so no persisted vault breaks.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            sealed = try c.decode(AEAD.Sealed.self, forKey: .sealed)
            sealedBlob = try c.decodeIfPresent(AEAD.Sealed.self, forKey: .sealedBlob)
            wrappedKey = try c.decode(WrappedKey.self, forKey: .wrappedKey)
            local = try c.decodeIfPresent(Bool.self, forKey: .local) ?? false
            padded = try c.decodeIfPresent(Bool.self, forKey: .padded) ?? false
        }
    }

    /// What gets uploaded as the opaque blob: the entry's ciphertext parts. The
    /// DEK (wrapped under the VK) travels separately as the entry's wrapped key.
    /// `padded` (optional for rows uploaded before padding existed) tells the
    /// pulling device whether to unpad after opening — a flag, not content.
    private struct BlobPayload: Codable {
        let sealed: AEAD.Sealed
        let sealedBlob: AEAD.Sealed?
        var padded: Bool? = nil
    }

    /// nil when the vault key can't be retrieved on this device. Entries then
    /// can't be decrypted (or newly sealed); surfaced via `keyState`. Never
    /// recovered by minting a replacement — only adopted from the user's identity
    /// bundle via the passphrase (SECURITY.md §3), which is why it's a `var`.
    private var vaultKey: SymmetricKey?
    private let fileURL: URL
    private let vault = "vault-A"
    private var client: BackendClient? // set after passkey-equivalent auth
    @Published private var entries: [StoredEntry] = []
    @Published private(set) var syncing = false
    @Published private(set) var syncedIDs: Set<UUID> = []
    /// Ids the user explicitly forgot (unreadable orphans). Persisted so `pull`
    /// never resurrects them from the server — without this, a forgotten
    /// server-origin row would be re-downloaded on every launch and the banner
    /// would come back forever. Ids only: nothing about content.
    private var forgottenIDs: Set<UUID> = []

    /// Live result of the last reconnect, for the DEBUG server-URL screen so its
    /// button reflects the real round-trip instead of optimistically claiming
    /// success. Not used in shipped UI.
    enum ConnState { case idle, connecting, connected, failed }
    @Published private(set) var connState: ConnState = .idle

    /// Whether this device holds the key that decrypts the vault. `.unavailable`
    /// means sealed entries exist but their VK isn't retrievable here (e.g. the
    /// Keychain item was lost to a signing/access-group change). We surface it
    /// rather than minting a new VK that would orphan everything.
    enum KeyState { case ready, unavailable }
    @Published private(set) var keyState: KeyState = .ready

    /// Only genuine captures count toward "pending sync" — the local-only demo
    /// seeds are never pushed, so counting them would strand the status at
    /// "N en attente" forever.
    var pendingSyncCount: Int { entries.filter { !$0.local && !syncedIDs.contains($0.id) }.count }

    /// How many stored entries can't currently be decrypted. > 0 means the Frise
    /// would otherwise drop them in silence; the UI shows an honest banner instead.
    /// Read from SwiftUI `body`, so it must stay cheap: `canDecrypt` (DEK unwrap +
    /// small content open) — never the full `decrypt`, whose eager media-blob open
    /// would re-decrypt every photo/audio on each render.
    var unreadableCount: Int { entries.reduce(0) { $0 + (canDecrypt($1) ? 0 : 1) } }

    init() {
        fileURL = Self.makeFileURL()
        let loaded = Self.load(from: fileURL)
        // Resolve the VK without ever regenerating it over existing sealed
        // entries (that would make every memory undecryptable). Only a genuinely
        // fresh vault — no entries on disk — gets a brand-new key. Decide from the
        // local `loaded`, not `self.entries`, which isn't readable until every
        // stored property is initialized.
        if let key = VaultKeychain.load() {
            vaultKey = key
            keyState = .ready
        } else if loaded?.entries.isEmpty ?? true {
            vaultKey = VaultKeychain.create()
            keyState = vaultKey == nil ? .unavailable : .ready
        } else {
            vaultKey = nil
            keyState = .unavailable
        }
        entries = loaded?.entries ?? []
        forgottenIDs = Set(loaded?.forgotten ?? [])
        // Authenticate (device keypair → session token) before syncing; the app
        // stays fully usable offline if it can't reach the backend (§2).
        Task { @MainActor in
            await authenticate()
            syncAll()
            pull(seedIfEmpty: loaded == nil && keyState == .ready)
        }
    }

    /// Passkey-equivalent login: register the device public key (idempotent), then
    /// challenge → sign → verify → session token. Best-effort.
    private func authenticate() async {
        // Resolved fresh each time so a changed server URL (dev) takes effect on
        // the next reconnect without a relaunch.
        let backendURL = BackendConfig.baseURL
        let auth = AuthClient(baseURL: backendURL)
        let device = DeviceIdentity.loadOrCreate()
        await auth.register(credentialID: device.credentialID, publicKeyX963: device.publicKeyX963, vault: vault)
        if let token = await auth.login(credentialID: device.credentialID, sign: device.sign) {
            client = BackendClient(baseURL: backendURL, token: token, vault: vault)
        }
    }

    /// Re-read the configured server URL, re-authenticate, then resync. Lets the
    /// dev server-URL setting take effect without relaunching the app. Best-effort
    /// and offline-safe like the launch path.
    func reconnect() {
        client = nil
        Task { @MainActor in
            connState = .connecting
            await authenticate()
            // `authenticate()` only sets `client` when the full register →
            // challenge → verify round-trip reached the server and returned a
            // session. So `client != nil` is the ground truth of "connected".
            connState = client != nil ? .connected : .failed
            syncAll()
            pull(seedIfEmpty: false)
        }
    }

    /// Push every not-yet-synced entry. Idempotent (content-addressed blobs +
    /// client-UUID entries), so this is safe to call on launch and after capture.
    func syncAll() {
        guard let client else { return }
        let pending = entries.filter { !$0.local && !syncedIDs.contains($0.id) }
        guard !pending.isEmpty else { return }
        Task { @MainActor in
            syncing = true
            for e in pending {
                // `pending` is a snapshot; each `await` below is a suspension point
                // where `forgetUnreadable()` may run. Re-check the entry still
                // exists so a just-forgotten orphan is never pushed to the server
                // (which has no delete route) nor ghost-inserted into syncedIDs.
                guard entries.contains(where: { $0.id == e.id }), !forgottenIDs.contains(e.id) else { continue }
                guard
                    let blob = try? JSONEncoder().encode(BlobPayload(sealed: e.sealed, sealedBlob: e.sealedBlob, padded: e.padded)),
                    let wk = try? JSONEncoder().encode(e.wrappedKey)
                else { continue }
                if await client.upload(entryID: e.id.uuidString, wrappedKeyB64: wk.base64EncodedString(), blob: blob),
                   entries.contains(where: { $0.id == e.id }) {
                    syncedIDs.insert(e.id)
                }
            }
            syncing = false
        }
    }

    /// Pull the vault from the server and merge by entry id (same-user
    /// multi-device, spike #3 — append-only journal, no concurrent wills, so the
    /// merge is a union with no lost updates, ARCHITECTURE.md §3/§4).
    func pull(seedIfEmpty: Bool) {
        guard let client else {
            if seedIfEmpty && entries.isEmpty { seedFromSamples(); syncAll() }
            return
        }
        Task { @MainActor in
            var added = false
            for row in await client.fetchDelta(since: 0) where row.committed {
                guard
                    let eid = UUID(uuidString: row.entryID),
                    !entries.contains(where: { $0.id == eid }),
                    !forgottenIDs.contains(eid), // the user forgot it — stays forgotten
                    let blobData = await client.blob(hash: row.blobHash),
                    let payload = try? JSONDecoder().decode(BlobPayload.self, from: blobData),
                    let wkData = Data(base64Encoded: row.wrappedKey),
                    let wrapped = try? JSONDecoder().decode(WrappedKey.self, from: wkData)
                else { continue }
                entries.append(StoredEntry(id: eid, sealed: payload.sealed, sealedBlob: payload.sealedBlob,
                                           wrappedKey: wrapped, padded: payload.padded ?? false))
                syncedIDs.insert(eid)
                added = true
            }
            if added { persist() }
            if entries.isEmpty && seedIfEmpty { seedFromSamples(); syncAll() }
        }
    }

    // MARK: identity — cross-device vault-key sharing (SECURITY.md §3)

    enum EnrollResult { case success, noKey, offline, failed }
    enum RecoverResult { case success(readable: Int), noBundle, wrongPassphrase, offline, failed }

    /// Run on the device that *holds* the vault key: wrap the VK under the
    /// identity's MIK, and wrap the MIK under a key derived from the user's
    /// passphrase (Argon2id). Publish only ciphertext + the (non-secret) salt, so
    /// another trusted device can recover the same VK from the passphrase. No
    /// memory is ever re-encrypted — the VK is unchanged (the §3 structural win).
    /// Uses `ensureMIK`, never a fresh key: the MIK is the SINGLE secret every
    /// door (passphrase, RK, device) wraps in parallel — minting one here would
    /// silently diverge from an already-published recovery bundle.
    func enrollPassphrase(_ passphrase: String) async -> EnrollResult {
        guard let vaultKey else { return .noKey }
        guard let client else { return .offline }
        guard let mik = ensureMIK() else { return .failed }
        do {
            let salt = try KDF.generateSalt()
            let kek = try await Self.deriveKEK(passphrase: passphrase, salt: salt)
            let wrappedMIK = try KeyWrap.wrap(mik, under: kek)
            let wrappedVK = try KeyWrap.wrap(vaultKey, under: mik)
            guard let wmB64 = Self.encodeWrapped(wrappedMIK), let wvB64 = Self.encodeWrapped(wrappedVK) else { return .failed }
            let bundle = BackendClient.IdentityBundle(saltB64: Data(salt).base64EncodedString(), wrappedMIK: wmB64, wrappedVK: wvB64)
            guard await client.putIdentity(bundle) else { return .offline }
            return .success
        } catch {
            return .failed
        }
    }

    /// Run on a device that does NOT yet hold the vault key: fetch the identity
    /// bundle, derive the KEK from the passphrase, unwrap MIK → VK, and *adopt*
    /// that VK as this device's vault key. A wrong passphrase fails the AEAD auth
    /// on the MIK unwrap — surfaced honestly, never a crash, never a guess.
    func recoverWithPassphrase(_ passphrase: String) async -> RecoverResult {
        guard let client else { return .offline }
        let fetched: BackendClient.IdentityBundle?
        do { fetched = try await client.getIdentity() } catch { return .offline }
        guard let bundle = fetched else { return .noBundle }
        guard
            let saltData = Data(base64Encoded: bundle.saltB64),
            let wrappedMIK = Self.decodeWrapped(bundle.wrappedMIK),
            let wrappedVK = Self.decodeWrapped(bundle.wrappedVK)
        else { return .failed }
        do {
            let kek = try await Self.deriveKEK(passphrase: passphrase, salt: Array(saltData))
            guard let mik = try? KeyWrap.unwrap(wrappedMIK, with: kek) else { return .wrongPassphrase }
            let vk = try KeyWrap.unwrap(wrappedVK, with: mik)
            return adopt(vk: vk, mik: mik)
        } catch {
            return .failed
        }
    }

    /// Argon2id is deliberately slow (~interactive limits, 64 MB); the store is
    /// @MainActor, so hop the derivation off it — otherwise every enroll/recover
    /// freezes the UI for the whole derivation.
    private static func deriveKEK(passphrase: String, salt: [UInt8]) async throws -> SymmetricKey {
        let pw = Array(passphrase.utf8)
        return try await Task.detached(priority: .userInitiated) {
            try SymmetricKey(bytes: KDF.deriveKey(password: pw, salt: salt))
        }.value
    }

    /// Adopt an identity's VK on this device — the single landing point of BOTH
    /// recovery doors (passphrase, guardian shares), so their behavior can't drift.
    private func adopt(vk: SymmetricKey, mik: SymmetricKey) -> RecoverResult {
        vaultKey = vk
        keyState = .ready
        SecureStore.save("vaultKey", Data(vk.bytes))
        SecureStore.save("mik", Data(mik.bytes))
        // Local demo seeds were sealed under this device's previous key — they are
        // scaffolding, not user data. Drop them and do NOT re-seed: a recovered
        // vault is a real vault, it must not gain fabricated memories.
        entries.removeAll { $0.local }
        let readable = entries.filter { !$0.local && canDecrypt($0) }.count
        persist()
        // Anything we skipped earlier (or new rows) can decrypt now.
        pull(seedIfEmpty: false)
        return .success(readable: readable)
    }

    // MARK: social recovery — Shamir 2-of-3 over the RK (SECURITY.md §5)

    enum RecoverySetupResult { case success([Shamir.Share]), noKey, offline, failed }

    /// Arm the catastrophe safety net: a Recovery Key wraps the same MIK the
    /// passphrase does (a parallel door onto the identity, §3), and the RK is
    /// Shamir 2-of-3-split. Only `MIK-under-RK` and `VK-under-MIK` are published;
    /// the three shares are returned to be handed to guardians and NEVER touch the
    /// server. Self-checks that any two shares rebuild the RK before claiming
    /// success (mirrors the §1.6 re-decryption ethos).
    func setupSocialRecovery() async -> RecoverySetupResult {
        guard let vaultKey else { return .noKey }
        guard let client else { return .offline }
        guard let mik = ensureMIK() else { return .failed }
        do {
            let rk = try RecoveryKey.generate()
            let shares = try Shamir.split(secret: rk.bytes, threshold: 2, shares: 3)
            guard let check = try? SymmetricKey(bytes: try Shamir.combine([shares[0], shares[1]])), check == rk
            else { return .failed }
            let wrappedMIK_RK = try KeyWrap.wrap(mik, under: rk)
            let wrappedVK = try KeyWrap.wrap(vaultKey, under: mik)
            guard let wmrk = Self.encodeWrapped(wrappedMIK_RK), let wvk = Self.encodeWrapped(wrappedVK)
            else { return .failed }
            guard await client.putRecovery(.init(wrappedMIK_RK: wmrk, wrappedVK: wvk)) else { return .offline }
            return .success(shares)
        } catch {
            return .failed
        }
    }

    /// Recover the vault on a keyless device from 2 (of 3) guardian shares: rebuild
    /// the RK, unwrap the MIK, then the VK, and adopt it — the same endpoint as the
    /// passphrase, reached through the social door. Fewer than 2 valid shares can't
    /// reconstruct the RK (Shamir), so this fails cleanly rather than guessing.
    func recoverWithShares(_ shares: [Shamir.Share]) async -> RecoverResult {
        guard let client else { return .offline }
        let fetched: BackendClient.RecoveryBundle?
        do { fetched = try await client.getRecovery() } catch { return .offline }
        guard let bundle = fetched else { return .noBundle }
        guard
            let wrappedMIK_RK = Self.decodeWrapped(bundle.wrappedMIK_RK),
            let wrappedVK = Self.decodeWrapped(bundle.wrappedVK)
        else { return .failed }
        do {
            let rk = try SymmetricKey(bytes: try Shamir.combine(shares))
            guard let mik = try? KeyWrap.unwrap(wrappedMIK_RK, with: rk) else { return .wrongPassphrase }
            let vk = try KeyWrap.unwrap(wrappedVK, with: mik)
            return adopt(vk: vk, mik: mik)
        } catch {
            return .failed
        }
    }

    /// The identity's Master Identity Key: load the device copy, or mint one on
    /// first use (a device with the VK but no MIK yet — e.g. recovery is armed
    /// before any passphrase enrollment). SECURITY.md §3: the MIK is the single
    /// secret every wrap (passphrase, RK, device-local) opens in parallel.
    private func ensureMIK() -> SymmetricKey? {
        if let d = SecureStore.load("mik"), let k = try? SymmetricKey(bytes: [UInt8](d)) { return k }
        guard let mik = try? MasterIdentityKey.generate() else { return nil }
        SecureStore.save("mik", Data(mik.bytes))
        return mik
    }

    /// Discard entries that cannot be decrypted with the current vault key —
    /// orphans sealed under a key this identity no longer holds (an old install,
    /// a pre-recovery device key). Gated on `keyState == .ready` so it never nukes
    /// a vault whose key is merely temporarily missing (there, recovery is the
    /// right move). Their key is gone for good (SECURITY.md §7), so this is honest
    /// cleanup, not the loss of anything recoverable.
    @discardableResult
    func forgetUnreadable() -> Int {
        guard keyState == .ready else { return 0 }
        let doomed = Set(entries.filter { !canDecrypt($0) }.map(\.id))
        guard !doomed.isEmpty else { return 0 }
        entries.removeAll { doomed.contains($0.id) }
        syncedIDs.subtract(doomed)
        // Remember the forgetting itself: `pull` skips these ids, so a
        // server-origin orphan can't resurrect on the next launch.
        forgottenIDs.formUnion(doomed)
        persist()
        return doomed.count
    }

    /// A guardian share as a portable string (index byte ‖ payload, base64). Handed
    /// to a guardian out-of-band; re-entered to recover. Never stored server-side.
    static func encodeShare(_ s: Shamir.Share) -> String {
        Data([s.index] + s.data).base64EncodedString()
    }

    static func decodeShare(_ str: String) -> Shamir.Share? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = Data(base64Encoded: trimmed), d.count >= 2 else { return nil }
        let bytes = [UInt8](d)
        return Shamir.Share(index: bytes[0], data: Array(bytes.dropFirst()))
    }

    private static func encodeWrapped(_ w: WrappedKey) -> String? {
        (try? JSONEncoder().encode(w))?.base64EncodedString()
    }

    private static func decodeWrapped(_ s: String) -> WrappedKey? {
        guard let d = Data(base64Encoded: s) else { return nil }
        return try? JSONDecoder().decode(WrappedKey.self, from: d)
    }

    // MARK: read

    func memories(for child: Child) -> [Memory] {
        entries
            .compactMap { decrypt($0) }
            .filter { $0.childID == child.id }
            .sorted { $0.daysAgo < $1.daysAgo }
    }

    // MARK: write

    func addCitation(childID: UUID, quote: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        add(childID: childID, kind: .citation,
            title: t.isEmpty ? "Citation" : t,
            note: "« \(quote.trimmingCharacters(in: .whitespacesAndNewlines)) »")
    }

    func addMeasure(childID: UUID, value: String) {
        add(childID: childID, kind: .measure, title: value.trimmingCharacters(in: .whitespacesAndNewlines), note: nil)
    }

    func addPhoto(childID: UUID, imageData: Data, kind: MemoryKind = .photo, title: String = "") {
        guard let stripped = ImageTools.stripExifJPEG(imageData) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = kind == .drawing ? "Dessin" : "Photo"
        add(childID: childID, kind: kind, title: t.isEmpty ? fallback : t, note: nil, blob: stripped)
    }

    func addMilestone(childID: UUID, label: String) {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        add(childID: childID, kind: .milestone, title: l.isEmpty ? "Jalon" : l, note: nil)
    }

    func addVoice(childID: UUID, audioData: Data, duration: String) {
        add(childID: childID, kind: .voice, title: "Note vocale", note: nil, audio: duration, blob: audioData)
    }

    // MARK: crypto core path

    private func add(childID: UUID, kind: MemoryKind, title: String, note: String?,
                     audio: String? = nil, blob: Data? = nil, createdAt: Date = Date(),
                     persistNow: Bool = true, local: Bool = false) {
        // No usable vault key → refuse rather than seal under a key we can't trust
        // to round-trip (keyState already tells the UI why).
        guard let vaultKey else { return }
        let content = Content(childID: childID, kind: kind, createdAt: createdAt, title: title, note: note, audio: audio)
        guard let payload = try? JSONEncoder().encode(content) else { return }
        do {
            let dek = try DataKey.generate()
            // Pad-by-tiers BEFORE sealing (SECURITY §6.2): the ciphertext size the
            // server sees is quantized, killing the exact-size fingerprint.
            let sealed = try AEAD.seal(Padding.pad(Array(payload)), key: dek.bytes)
            let sealedBlob = try blob.map { try AEAD.seal(Padding.pad(Array($0)), key: dek.bytes) }
            let wrapped = try KeyWrap.wrap(dek, under: vaultKey)
            entries.append(StoredEntry(id: UUID(), sealed: sealed, sealedBlob: sealedBlob, wrappedKey: wrapped,
                                       local: local, padded: true))
            if persistNow { persist(); syncAll() }
        } catch {
            // A failed encrypt must never surface a half-written entry (SECURITY.md §1.6).
        }
    }

    /// Cheap readability test: DEK unwrap + small-content open only — never the
    /// media blob. This is what render-path counters (`unreadableCount`) and bulk
    /// scans (`forgetUnreadable`, `adopt`) use; `decrypt` stays the display path.
    private func canDecrypt(_ e: StoredEntry) -> Bool {
        guard let vaultKey, let dek = try? KeyWrap.unwrap(e.wrappedKey, with: vaultKey) else { return false }
        return (try? AEAD.open(e.sealed, key: dek.bytes)) != nil
    }

    /// Open, then unpad when the entry was padded-by-tiers (§6.2). Pre-padding
    /// entries pass through unchanged.
    private func openPlain(_ sealed: AEAD.Sealed, dek: SymmetricKey, padded: Bool) -> [UInt8]? {
        guard let opened = try? AEAD.open(sealed, key: dek.bytes) else { return nil }
        return padded ? (try? Padding.unpad(opened)) : opened
    }

    private func decrypt(_ e: StoredEntry) -> Memory? {
        guard
            let vaultKey,
            let dek = try? KeyWrap.unwrap(e.wrappedKey, with: vaultKey),
            let plain = openPlain(e.sealed, dek: dek, padded: e.padded),
            let content = try? JSONDecoder().decode(Content.self, from: Data(plain))
        else { return nil }

        let days = max(0, Calendar.current.dateComponents([.day], from: content.createdAt, to: Date()).day ?? 0)
        let blob = e.sealedBlob.flatMap { openPlain($0, dek: dek, padded: e.padded) }.map { Data($0) }
        return Memory(id: e.id, childID: content.childID, kind: content.kind, daysAgo: days,
                      title: content.title, note: content.note, audio: content.audio, pastel: content.kind.gradient,
                      imageData: content.kind.hasPhoto ? blob : nil,
                      audioData: content.kind == .voice ? blob : nil)
    }

    // MARK: persistence

    /// On-disk shape: sealed entries + the ids the user forgot. Ids are opaque
    /// UUIDs — nothing about content leaks from this file beyond what the sealed
    /// entries already are (ciphertext).
    private struct VaultFile: Codable {
        var entries: [StoredEntry]
        var forgotten: [UUID]
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(VaultFile(entries: entries, forgotten: Array(forgottenIDs))) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> VaultFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let file = try? JSONDecoder().decode(VaultFile.self, from: data) { return file }
        // Pre-`forgotten` format: a bare entry array. Migrate on next persist.
        if let entries = try? JSONDecoder().decode([StoredEntry].self, from: data) {
            return VaultFile(entries: entries, forgotten: [])
        }
        return nil
    }

    private static func makeFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Souvenir", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("memories.json")
    }

    private func seedFromSamples() {
        // 30 demo souvenirs across ~3 years for both children (FriseModels), so a
        // fresh vault feels lived-in. Civil date travels encrypted via createdAt.
        for m in SampleData.demoMemories() {
            add(childID: m.childID, kind: m.kind, title: m.title, note: m.note,
                audio: m.audio, createdAt: m.date, persistNow: false, local: true)
        }
        persist()
    }
}
