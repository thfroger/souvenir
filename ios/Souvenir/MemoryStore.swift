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
    static func loadOrCreate() -> SymmetricKey {
        if let data = SecureStore.load("vaultKey"), let key = try? SymmetricKey(bytes: [UInt8](data)) { return key }
        let key = (try? VaultKey.generate()) ?? ((try? SymmetricKey(bytes: [UInt8](repeating: 0, count: 32)))!)
        SecureStore.save("vaultKey", Data(key.bytes))
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
    }

    /// What gets uploaded as the opaque blob: the entry's ciphertext parts. The
    /// DEK (wrapped under the VK) travels separately as the entry's wrapped key.
    private struct BlobPayload: Codable {
        let sealed: AEAD.Sealed
        let sealedBlob: AEAD.Sealed?
    }

    private let vaultKey: SymmetricKey
    private let fileURL: URL
    private let backendURL = URL(string: "http://localhost:8787")!
    private let vault = "vault-A"
    private var client: BackendClient? // set after passkey-equivalent auth
    @Published private var entries: [StoredEntry] = []
    @Published private(set) var syncing = false
    @Published private(set) var syncedIDs: Set<UUID> = []

    var pendingSyncCount: Int { entries.count - syncedIDs.count }

    init() {
        vaultKey = VaultKeychain.loadOrCreate()
        fileURL = Self.makeFileURL()
        let loaded = Self.load(from: fileURL)
        entries = loaded ?? []
        // Authenticate (device keypair → session token) before syncing; the app
        // stays fully usable offline if it can't reach the backend (§2).
        Task { @MainActor in
            await authenticate()
            syncAll()
            pull(seedIfEmpty: loaded == nil)
        }
    }

    /// Passkey-equivalent login: register the device public key (idempotent), then
    /// challenge → sign → verify → session token. Best-effort.
    private func authenticate() async {
        let auth = AuthClient(baseURL: backendURL)
        let device = DeviceIdentity.loadOrCreate()
        await auth.register(credentialID: device.credentialID, publicKeyX963: device.publicKeyX963, vault: vault)
        if let token = await auth.login(credentialID: device.credentialID, sign: device.sign) {
            client = BackendClient(baseURL: backendURL, token: token, vault: vault)
        }
    }

    /// Push every not-yet-synced entry. Idempotent (content-addressed blobs +
    /// client-UUID entries), so this is safe to call on launch and after capture.
    func syncAll() {
        guard let client else { return }
        let pending = entries.filter { !syncedIDs.contains($0.id) }
        guard !pending.isEmpty else { return }
        Task { @MainActor in
            syncing = true
            for e in pending {
                guard
                    let blob = try? JSONEncoder().encode(BlobPayload(sealed: e.sealed, sealedBlob: e.sealedBlob)),
                    let wk = try? JSONEncoder().encode(e.wrappedKey)
                else { continue }
                if await client.upload(entryID: e.id.uuidString, wrappedKeyB64: wk.base64EncodedString(), blob: blob) {
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
                    let blobData = await client.blob(hash: row.blobHash),
                    let payload = try? JSONDecoder().decode(BlobPayload.self, from: blobData),
                    let wkData = Data(base64Encoded: row.wrappedKey),
                    let wrapped = try? JSONDecoder().decode(WrappedKey.self, from: wkData)
                else { continue }
                entries.append(StoredEntry(id: eid, sealed: payload.sealed, sealedBlob: payload.sealedBlob, wrappedKey: wrapped))
                syncedIDs.insert(eid)
                added = true
            }
            if added { persist() }
            if entries.isEmpty && seedIfEmpty { seedFromSamples(); syncAll() }
        }
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

    func addPhoto(childID: UUID, imageData: Data, title: String = "Photo") {
        guard let stripped = ImageTools.stripExifJPEG(imageData) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        add(childID: childID, kind: .photo, title: t.isEmpty ? "Photo" : t, note: nil, blob: stripped)
    }

    func addVoice(childID: UUID, audioData: Data, duration: String) {
        add(childID: childID, kind: .voice, title: "Note vocale", note: nil, audio: duration, blob: audioData)
    }

    // MARK: crypto core path

    private func add(childID: UUID, kind: MemoryKind, title: String, note: String?,
                     audio: String? = nil, blob: Data? = nil, createdAt: Date = Date(), persistNow: Bool = true) {
        let content = Content(childID: childID, kind: kind, createdAt: createdAt, title: title, note: note, audio: audio)
        guard let payload = try? JSONEncoder().encode(content) else { return }
        do {
            let dek = try DataKey.generate()
            let sealed = try AEAD.seal(Array(payload), key: dek.bytes)
            let sealedBlob = try blob.map { try AEAD.seal(Array($0), key: dek.bytes) }
            let wrapped = try KeyWrap.wrap(dek, under: vaultKey)
            entries.append(StoredEntry(id: UUID(), sealed: sealed, sealedBlob: sealedBlob, wrappedKey: wrapped))
            if persistNow { persist(); syncAll() }
        } catch {
            // A failed encrypt must never surface a half-written entry (SECURITY.md §1.6).
        }
    }

    private func decrypt(_ e: StoredEntry) -> Memory? {
        guard
            let dek = try? KeyWrap.unwrap(e.wrappedKey, with: vaultKey),
            let plain = try? AEAD.open(e.sealed, key: dek.bytes),
            let content = try? JSONDecoder().decode(Content.self, from: Data(plain))
        else { return nil }

        let days = max(0, Calendar.current.dateComponents([.day], from: content.createdAt, to: Date()).day ?? 0)
        let blob = e.sealedBlob.flatMap { try? AEAD.open($0, key: dek.bytes) }.map { Data($0) }
        return Memory(childID: content.childID, kind: content.kind, daysAgo: days,
                      title: content.title, note: content.note, audio: content.audio, pastel: content.kind.gradient,
                      imageData: content.kind.hasPhoto ? blob : nil,
                      audioData: content.kind == .voice ? blob : nil)
    }

    // MARK: persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [StoredEntry]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([StoredEntry].self, from: data)
    }

    private static func makeFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Souvenir", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("memories.json")
    }

    private func seedFromSamples() {
        for child in SampleData.children {
            for m in SampleData.memories(for: child) {
                add(childID: child.id, kind: m.kind, title: m.title, note: m.note,
                    audio: m.audio, createdAt: m.date, persistNow: false)
            }
        }
        persist()
    }
}
