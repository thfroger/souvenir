import Foundation
import CryptoKit

/// The device's signing identity for passkey-equivalent auth (SECURITY.md §2.2/§6.3):
/// a P-256 keypair — Secure Enclave-backed on a real device (non-extractable),
/// software on the simulator (dev only) — plus a stable credential id. The
/// private key never leaves the device; auth proves possession by signing a
/// server challenge. The biometric gate is the app's entry ritual (LockView).
struct DeviceIdentity {
    let credentialID: String
    let publicKeyX963: String       // base64 of the 65-byte X9.63 point
    private let signer: (Data) -> Data?

    func sign(_ data: Data) -> Data? { signer(data) }

    static func loadOrCreate() -> DeviceIdentity {
        let credentialID: String
        if let d = SecureStore.load("credentialID"), let s = String(data: d, encoding: .utf8) {
            credentialID = s
        } else {
            credentialID = UUID().uuidString
            SecureStore.save("credentialID", Data(credentialID.utf8))
        }
        let (publicKey, signer) = SecureEnclave.isAvailable ? secureEnclaveKey() : softwareKey()
        return DeviceIdentity(credentialID: credentialID, publicKeyX963: publicKey, signer: signer)
    }

    private static func secureEnclaveKey() -> (String, (Data) -> Data?) {
        if let d = SecureStore.load("deviceKey"), let k = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: d) {
            return identity(k)
        }
        if let k = try? SecureEnclave.P256.Signing.PrivateKey() {
            SecureStore.save("deviceKey", k.dataRepresentation)
            return identity(k)
        }
        return softwareKey() // graceful fallback if SE creation fails
    }

    private static func softwareKey() -> (String, (Data) -> Data?) {
        let key: P256.Signing.PrivateKey
        if let d = SecureStore.load("deviceKey"), let existing = try? P256.Signing.PrivateKey(rawRepresentation: d) {
            key = existing
        } else {
            key = P256.Signing.PrivateKey()
            SecureStore.save("deviceKey", key.rawRepresentation)
        }
        return identity(key)
    }

    private static func identity(_ k: SecureEnclave.P256.Signing.PrivateKey) -> (String, (Data) -> Data?) {
        (k.publicKey.x963Representation.base64EncodedString(), { try? k.signature(for: $0).derRepresentation })
    }
    private static func identity(_ k: P256.Signing.PrivateKey) -> (String, (Data) -> Data?) {
        (k.publicKey.x963Representation.base64EncodedString(), { try? k.signature(for: $0).derRepresentation })
    }
}
