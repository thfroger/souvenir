import Foundation
import Clibsodium

/// Authenticated encryption with XChaCha20-Poly1305 (IETF).
/// One disposable data key (DEK) per memory encrypts the blob (SECURITY.md §3).
public enum AEAD {
    public static let keyBytes = crypto_aead_xchacha20poly1305_ietf_keybytes()
    public static let nonceBytes = crypto_aead_xchacha20poly1305_ietf_npubbytes()
    public static let tagBytes = crypto_aead_xchacha20poly1305_ietf_abytes()

    public struct Sealed: Equatable, Codable {
        public let nonce: [UInt8]
        public let ciphertext: [UInt8] // includes the Poly1305 tag

        public init(nonce: [UInt8], ciphertext: [UInt8]) {
            self.nonce = nonce
            self.ciphertext = ciphertext
        }

        // Persist as base64 (Data) rather than JSON int arrays — for encrypted
        // blobs at rest (SECURITY.md §6.4). The bytes are already ciphertext.
        enum CodingKeys: String, CodingKey { case nonce, ciphertext }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nonce = Array(try c.decode(Data.self, forKey: .nonce))
            ciphertext = Array(try c.decode(Data.self, forKey: .ciphertext))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(Data(nonce), forKey: .nonce)
            try c.encode(Data(ciphertext), forKey: .ciphertext)
        }
    }

    public static func seal(_ plaintext: [UInt8], key: [UInt8], aad: [UInt8] = []) throws -> Sealed {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard key.count == keyBytes else { throw CryptoError.invalidLength }

        var nonce = [UInt8](repeating: 0, count: nonceBytes)
        randombytes_buf(&nonce, nonceBytes)

        var cipher = [UInt8](repeating: 0, count: plaintext.count + tagBytes)
        var clen: UInt64 = 0
        let rc = crypto_aead_xchacha20poly1305_ietf_encrypt(
            &cipher, &clen,
            plaintext, UInt64(plaintext.count),
            aad, UInt64(aad.count),
            nil, nonce, key
        )
        guard rc == 0 else { throw CryptoError.decryptionFailed }
        if Int(clen) != cipher.count { cipher = Array(cipher.prefix(Int(clen))) }
        return Sealed(nonce: nonce, ciphertext: cipher)
    }

    public static func open(_ sealed: Sealed, key: [UInt8], aad: [UInt8] = []) throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard key.count == keyBytes, sealed.nonce.count == nonceBytes else { throw CryptoError.invalidLength }

        var plain = [UInt8](repeating: 0, count: max(sealed.ciphertext.count, 0))
        var plen: UInt64 = 0
        let rc = crypto_aead_xchacha20poly1305_ietf_decrypt(
            &plain, &plen,
            nil,
            sealed.ciphertext, UInt64(sealed.ciphertext.count),
            aad, UInt64(aad.count),
            sealed.nonce, key
        )
        guard rc == 0 else { throw CryptoError.decryptionFailed }
        return Array(plain.prefix(Int(plen)))
    }
}
