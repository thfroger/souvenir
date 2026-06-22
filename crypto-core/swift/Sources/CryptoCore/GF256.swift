import Clibsodium

/// Arithmetic in GF(2^8) with the AES reduction polynomial 0x11b.
/// Multiplication is branchless (no secret-dependent branches or table lookups,
/// so no cache-timing side channel) — used by the Shamir implementation.
enum GF256 {
    @inline(__always) static func add(_ a: UInt8, _ b: UInt8) -> UInt8 { a ^ b }

    @inline(__always) static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var a = a
        var b = b
        var p: UInt8 = 0
        for _ in 0..<8 {
            let lowBit = UInt8(0) &- (b & 1)          // 0xFF if b&1 else 0x00
            p ^= a & lowBit
            let highSet = UInt8(0) &- ((a >> 7) & 1)  // 0xFF if a's high bit set
            a = (a &<< 1) ^ (0x1b & highSet)
            b >>= 1
        }
        return p
    }

    /// a^n by square-and-multiply. The exponent is a fixed constant (254) in our
    /// use, so the branch pattern is independent of the secret value `a`.
    @inline(__always) static func pow(_ a: UInt8, _ n: Int) -> UInt8 {
        var result: UInt8 = 1
        var base = a
        var e = n
        while e > 0 {
            if e & 1 == 1 { result = mul(result, base) }
            base = mul(base, base)
            e >>= 1
        }
        return result
    }

    /// Multiplicative inverse: a^(2^8 - 2) = a^254 (defined for a != 0).
    @inline(__always) static func inv(_ a: UInt8) -> UInt8 { pow(a, 254) }
}
