import Clibsodium

/// Social recovery: the Recovery Key (RK) is split 2-of-3 across guardians
/// (SECURITY.md §5). It is the RK that is split — never the MIK directly.
///
/// Byte-wise Shamir secret sharing over GF(2^8). For each byte of the payload a
/// polynomial of degree `threshold-1` is drawn whose constant term is the secret
/// byte; shares are evaluations at x = 1...n. Any `threshold` shares reconstruct
/// the secret by Lagrange interpolation at x = 0; fewer reveal nothing.
///
/// Integrity: the payload is `secret || BLAKE2b(secret, 16)`. On combine the tag
/// is recomputed and compared in constant time, so a corrupted share (or too few
/// distinct shares) is detected instead of returning a silently-wrong key. The
/// downstream `MIK-wrapped-under-RK` AEAD unwrap (§5) is a second, independent
/// check.
///
/// NOTE: still subject to external audit before freeze (SECURITY.md §8.4) — that
/// review is what makes "frozen crypto core" a verifiable claim, not this comment.
public enum Shamir {
    public struct Share: Equatable {
        public let index: UInt8   // the x coordinate (1...255), never 0
        public let data: [UInt8]  // one byte per payload byte (secret + tag)
        public init(index: UInt8, data: [UInt8]) {
            self.index = index
            self.data = data
        }
    }

    static let tagBytes = 16

    public static func split(secret: [UInt8], threshold: Int = 2, shares: Int = 3) throws -> [Share] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard !secret.isEmpty else { throw CryptoError.invalidLength }
        guard threshold >= 2, shares >= threshold, shares <= 255 else { throw CryptoError.invalidShares }

        let payload = secret + tag(secret)
        let degree = threshold - 1

        // Per byte: random coefficients a1...a_{degree}. The LEADING coefficient
        // must be non-zero, otherwise the polynomial degenerates to a lower degree
        // and fewer than `threshold` shares could leak that byte.
        var coeffs = [[UInt8]](repeating: [UInt8](repeating: 0, count: degree), count: payload.count)
        for k in 0..<payload.count {
            var c = [UInt8](repeating: 0, count: degree)
            if degree > 0 {
                randombytes_buf(&c, degree)
                c[degree - 1] = nonzeroRandomByte()
            }
            coeffs[k] = c
        }

        var result: [Share] = []
        result.reserveCapacity(shares)
        for x in 1...shares {
            let xb = UInt8(x)
            var data = [UInt8](repeating: 0, count: payload.count)
            for k in 0..<payload.count {
                var y = payload[k] // constant term a0 = secret/tag byte
                var xpow = xb
                for d in 0..<degree {
                    y ^= GF256.mul(coeffs[k][d], xpow)
                    xpow = GF256.mul(xpow, xb)
                }
                data[k] = y
            }
            result.append(Share(index: xb, data: data))
        }
        return result
    }

    public static func combine(_ shares: [Share]) throws -> [UInt8] {
        guard Sodium.ensureInit() else { throw CryptoError.initFailed }
        guard shares.count >= 2 else { throw CryptoError.invalidShares }

        let indices = shares.map(\.index)
        guard !indices.contains(0), Set(indices).count == indices.count else { throw CryptoError.invalidShares }

        let len = shares[0].data.count
        guard len > tagBytes, shares.allSatisfy({ $0.data.count == len }) else { throw CryptoError.invalidShares }

        var payload = [UInt8](repeating: 0, count: len)
        for k in 0..<len {
            payload[k] = interpolateAtZero(points: shares.map { ($0.index, $0.data[k]) })
        }

        let secret = Array(payload[0..<(len - tagBytes)])
        let recoveredTag = Array(payload[(len - tagBytes)...])
        guard constantTimeEqual(recoveredTag, tag(secret)) else { throw CryptoError.shareIntegrityFailed }
        return secret
    }

    // MARK: - internals

    /// Lagrange interpolation evaluated at x = 0. In GF(2^8) subtraction is XOR,
    /// so (0 - x_j) = x_j and (x_i - x_j) = x_i ^ x_j.
    private static func interpolateAtZero(points: [(UInt8, UInt8)]) -> UInt8 {
        var secret: UInt8 = 0
        for i in 0..<points.count {
            let (xi, yi) = points[i]
            var num: UInt8 = 1
            var den: UInt8 = 1
            for j in 0..<points.count where j != i {
                let xj = points[j].0
                num = GF256.mul(num, xj)
                den = GF256.mul(den, xi ^ xj)
            }
            secret ^= GF256.mul(yi, GF256.mul(num, GF256.inv(den)))
        }
        return secret
    }

    private static func tag(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: tagBytes)
        _ = crypto_generichash(&out, tagBytes, data, UInt64(data.count), nil, 0)
        return out
    }

    private static func nonzeroRandomByte() -> UInt8 {
        var b: UInt8 = 0
        repeat { randombytes_buf(&b, 1) } while b == 0
        return b
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return sodium_memcmp(a, b, a.count) == 0
    }
}
