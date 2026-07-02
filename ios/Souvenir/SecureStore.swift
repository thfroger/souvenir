import Foundation
import Security

/// Small named secret store: Keychain primary (Secure Enclave-backed on a signed
/// device, SECURITY.md §3), with a **DEBUG-only** file fallback for the unsigned
/// simulator build (SecItemAdd → errSecMissingEntitlement -34018) and for dev
/// signing-team changes that strand the Keychain access group.
///
/// Release builds NEVER write a secret to a file — every file write in here is
/// compiled out of a signed build, which is what keeps the §3 "Keychain-only"
/// claim true rather than merely asserted. Release builds may still *read* a
/// leftover dev file once, and immediately self-heal it into the Keychain.
enum SecureStore {
    private static let service = "app.souvenir"

    static func load(_ account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            #if DEBUG
            // Backfill the dev mirror for vaults created before mirroring existed,
            // so a later signing-team change can still be rescued by the file.
            if !FileManager.default.fileExists(atPath: fileURL(account).path) {
                try? data.write(to: fileURL(account), options: .completeFileProtection)
            }
            #endif
            return data
        }
        // Keychain miss → dev-file fallback (written only by DEBUG builds). If it
        // rescues the secret, self-heal the Keychain so the next load no longer
        // depends on the file at all.
        guard let data = try? Data(contentsOf: fileURL(account)) else { return nil }
        save(account, data)
        return data
    }

    @discardableResult
    static func save(_ account: String, _ data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        #if DEBUG
        // Dev only: always mirror. Between installs the signing team — and thus
        // the Keychain access group — can change, stranding the item while the app
        // container (and its sealed entries) survive; the mirror keeps the vault
        // openable. Compiled out of signed builds.
        try? data.write(to: fileURL(account), options: .completeFileProtection)
        #else
        // Release: never write a secret to a file. Once the Keychain holds it,
        // also remove any leftover dev-build mirror so no file copy lingers.
        if ok { try? FileManager.default.removeItem(at: fileURL(account)) }
        #endif
        return ok
    }

    private static func fileURL(_ account: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Souvenir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(account).bin")
    }
}
