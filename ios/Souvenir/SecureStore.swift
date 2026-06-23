import Foundation
import Security

/// Small named secret store: Keychain primary (Secure Enclave-backed on a signed
/// device, SECURITY.md §3), with a dev-only file fallback for the unsigned
/// simulator build where SecItemAdd returns errSecMissingEntitlement (-34018).
/// The file fallback never ships.
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
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data { return data }
        return (try? Data(contentsOf: fileURL(account)))
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
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return true }
        try? data.write(to: fileURL(account), options: .completeFileProtection) // dev fallback
        return false
    }

    private static func fileURL(_ account: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Souvenir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(account).bin")
    }
}
