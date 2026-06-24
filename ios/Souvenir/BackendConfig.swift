import Foundation

/// Single source of truth for where the app reaches the "dumb" blob store.
///
/// On the simulator `localhost` resolves to the host Mac, so the default just
/// works. On a physical iPhone `localhost` is the phone itself — it can't reach
/// the Mac's dev backend — so a developer can point the app at the Mac's LAN IP
/// (IMPLEMENTATION.md "URL backend configurable").
///
/// This override is a **DEBUG-only dev convenience** and is never surfaced in a
/// shipped, signed build (CLAUDE.md — "replis dev qui ne shippent pas"). It only
/// ever holds a server *address*: no secret, no cleartext, nothing about a child.
enum BackendConfig {
    static let overrideKey = "backendURLOverride"

    /// Simulator default. Reaches the host Mac's `node src/server.js` on :8787.
    static let fallback = URL(string: "http://localhost:8787")!

    /// Resolved base URL: the saved override if it still parses, else localhost.
    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let url = normalized(raw) {
            return url
        }
        return fallback
    }

    /// The raw text the user last saved (for re-display in the field), if any.
    static var overrideText: String? {
        UserDefaults.standard.string(forKey: overrideKey)
    }

    /// True when the app is currently pointed at a custom server.
    static var hasOverride: Bool {
        guard let raw = overrideText else { return false }
        return normalized(raw) != nil
    }

    /// Persist a user-typed value. Empty input clears the override (back to
    /// localhost). Returns the resolved URL when accepted, `nil` when the input
    /// can't be parsed into a host.
    @discardableResult
    static func setOverride(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearOverride()
            return fallback
        }
        guard let url = normalized(trimmed) else { return nil }
        UserDefaults.standard.set(trimmed, forKey: overrideKey)
        return url
    }

    static func clearOverride() {
        UserDefaults.standard.removeObject(forKey: overrideKey)
    }

    /// Forgiving parse so a developer can type just the Mac's IP. Accepts a bare
    /// host ("192.168.1.20"), host:port, or a full URL; a missing scheme becomes
    /// `http://` and a missing port becomes the backend's default `:8787`.
    static func normalized(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let withScheme = s.contains("://") ? s : "http://\(s)"
        guard var comps = URLComponents(string: withScheme),
              let host = comps.host, !host.isEmpty else { return nil }
        if comps.port == nil { comps.port = 8787 }
        return comps.url
    }
}
