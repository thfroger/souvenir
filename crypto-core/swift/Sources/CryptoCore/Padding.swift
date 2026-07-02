import Clibsodium

/// Padding-by-tiers of every blob BEFORE encryption (SECURITY.md §6.2, [FIGÉ]).
/// The exact byte size of a ciphertext is a fingerprint ("does this user hold
/// *this* file?", a de-anonymisation vector); quantizing every plaintext onto a
/// moderate geometric scale kills the exact fingerprint for a bounded storage
/// overhead, and the common floor makes the small content blobs (note, mesure,
/// citation, profil) mutually indistinguishable.
///
/// The padding itself is libsodium's ISO/IEC 7816-4 (`sodium_pad`/`sodium_unpad`)
/// — nothing hand-rolled (SECURITY.md §3). Only the tier *scale* is ours:
///
///   tier(n) = smallest t in { floor · ratio^k } with t > n   (strictly:
///   7816-4 always adds ≥ 1 byte, so a payload exactly at a tier moves up)
///
/// `floorBytes`/`ratio` are provisional, [À VALIDER PAR SPIKE] (ARCHITECTURE.md
/// §6): ratio 1.25 bounds the worst-case overhead at +25 % (average ≈ +11 % on
/// a uniform size distribution); NOT a power-of-two scale (§6.2).
public enum Padding {
    /// Common floor for small content blobs (§6.2 « plancher commun »).
    public static let floorBytes = 1024
    /// Moderate geometric ratio (deliberately not 2).
    public static let ratio = 1.25

    /// The tier a payload of `n` bytes pads to (strictly greater than `n`).
    public static func tier(for n: Int) -> Int {
        precondition(n >= 0)
        var t = floorBytes
        while t <= n { t = Int((Double(t) * ratio).rounded(.up)) }
        return t
    }

    /// Pad to the payload's tier. Returns a buffer of exactly `tier(for: count)`.
    public static func pad(_ bytes: [UInt8]) throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        let target = tier(for: bytes.count)
        var buf = bytes + [UInt8](repeating: 0, count: target - bytes.count)
        var paddedLen: size_t = 0
        // blocksize == target and count < target, so the next multiple is target.
        let rc = sodium_pad(&paddedLen, &buf, size_t(bytes.count), size_t(target), size_t(buf.count))
        guard rc == 0, Int(paddedLen) == target else { throw CryptoError.invalidPadding }
        return buf
    }

    /// Recover the original payload. Fails cleanly on a corrupt (or never
    /// padded) buffer — never a guess (TESTING.md §1 ethos).
    public static func unpad(_ bytes: [UInt8]) throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard !bytes.isEmpty else { throw CryptoError.invalidPadding }
        var unpaddedLen: size_t = 0
        let rc = sodium_unpad(&unpaddedLen, bytes, size_t(bytes.count), size_t(bytes.count))
        guard rc == 0, Int(unpaddedLen) <= bytes.count else { throw CryptoError.invalidPadding }
        return Array(bytes.prefix(Int(unpaddedLen)))
    }
}
