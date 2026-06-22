import Foundation

/// Social recovery: the Recovery Key (RK) is split 2-of-3 across guardians
/// (SECURITY.md §5). It is the RK that is split — never the MIK directly.
///
/// PENDING — deliberately not implemented yet. The crypto core is frozen and
/// audited (SECURITY.md §1.5): Shamir secret sharing over GF(256) must be a
/// carefully reviewed / vetted implementation, with constant-time field ops,
/// not hand-rolled in a skeleton and forgotten. Implement against the test
/// vectors and the full TESTING.md §1 Shamir suite (every 2-of-3 subset
/// reconstructs; 1 share fails; corrupted shares detected; RK rotation).
public enum Shamir {
    public struct Share: Equatable {
        public let index: UInt8
        public let data: [UInt8]
        public init(index: UInt8, data: [UInt8]) {
            self.index = index
            self.data = data
        }
    }

    public static func split(secret: [UInt8], threshold: Int = 2, shares: Int = 3) throws -> [Share] {
        throw CryptoError.notImplemented("Shamir.split — SECURITY.md §5 / TESTING.md §1")
    }

    public static func combine(_ shares: [Share]) throws -> [UInt8] {
        throw CryptoError.notImplemented("Shamir.combine — SECURITY.md §5 / TESTING.md §1")
    }
}
