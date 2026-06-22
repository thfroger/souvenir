import Csodium

/// Password-based key derivation with Argon2id (SECURITY.md §3).
/// Used to derive the key that wraps the MIK; changing the password re-wraps
/// the MIK only, never the memories.
public enum KDF {
    public static let saltBytes = Int(crypto_pwhash_saltbytes())

    /// NOTE: the parameters below are the libsodium "interactive" presets, chosen
    /// to keep tests/CI fast. The FINAL production parameters are a target
    /// decision (OWASP MASVS L2, SECURITY.md §3/§8.4) — `[À VALIDER]` before freeze.
    public static func deriveKey(
        password: [UInt8],
        salt: [UInt8],
        outputBytes: Int = 32,
        opsLimit: UInt64 = UInt64(crypto_pwhash_opslimit_interactive()),
        memLimit: Int = crypto_pwhash_memlimit_interactive()
    ) throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard salt.count == saltBytes else { throw CryptoError.invalidLength }
        guard !password.isEmpty else { throw CryptoError.invalidLength }

        var out = [UInt8](repeating: 0, count: outputBytes)
        let rc = password.withUnsafeBytes { raw -> Int32 in
            let p = raw.bindMemory(to: CChar.self).baseAddress!
            return crypto_pwhash(
                &out, UInt64(outputBytes),
                p, UInt64(password.count),
                salt,
                opsLimit, memLimit,
                crypto_pwhash_alg_argon2id13()
            )
        }
        guard rc == 0 else { throw CryptoError.initFailed }
        return out
    }

    public static func generateSalt() throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        var s = [UInt8](repeating: 0, count: saltBytes)
        randombytes_buf(&s, s.count)
        return s
    }
}
