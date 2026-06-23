import Clibsodium

/// A 32-byte symmetric key. Every tier of the hierarchy (SECURITY.md §3) is a
/// symmetric key; the *role* is what the wrapping graph encodes.
public struct SymmetricKey: Equatable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == AEAD.keyBytes else { throw CryptoError.invalidLength }
        self.bytes = bytes
    }

    public static func generate() throws -> SymmetricKey {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        var b = [UInt8](repeating: 0, count: AEAD.keyBytes)
        randombytes_buf(&b, b.count)
        return try SymmetricKey(bytes: b)
    }
}

// Named roles in the key hierarchy (SECURITY.md §3).
public typealias DataKey = SymmetricKey           // DEK — one per memory
public typealias VaultKey = SymmetricKey          // VK — wraps a vault's DEKs
public typealias MasterIdentityKey = SymmetricKey // MIK — the user's only true secret
public typealias RecoveryKey = SymmetricKey       // RK — Shamir-split across guardians (§5)

/// A key encrypted under another key.
public struct WrappedKey: Equatable, Codable {
    public let sealed: AEAD.Sealed
    public init(sealed: AEAD.Sealed) { self.sealed = sealed }
}

/// Key wrapping is the load-bearing operation of the hierarchy: DEK under VK,
/// VK under MIK, MIK under {password-derived key, device-local key, RK}.
/// A bad wrap fails cleanly, never silently (TESTING.md §1).
public enum KeyWrap {
    public static func wrap(_ inner: SymmetricKey, under outer: SymmetricKey) throws -> WrappedKey {
        WrappedKey(sealed: try AEAD.seal(inner.bytes, key: outer.bytes))
    }

    public static func unwrap(_ wrapped: WrappedKey, with outer: SymmetricKey) throws -> SymmetricKey {
        try SymmetricKey(bytes: AEAD.open(wrapped.sealed, key: outer.bytes))
    }
}
