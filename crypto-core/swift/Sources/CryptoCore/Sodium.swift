import Clibsodium

/// libsodium must be initialized once before use. `sodium_init()` is idempotent
/// and thread-safe; we memoize the result.
enum Sodium {
    static let isReady: Bool = {
        sodium_init() >= 0
    }()

    @discardableResult
    static func ensureInit() -> Bool { isReady }
}
