import SwiftUI

// Design tokens from DESIGN.md §2 / README.md (paper-cream editorial palette).
// Instrument Serif / Hanken / Geist Mono are not bundled yet → system fallbacks
// (.serif / .default / .monospaced) until the real fonts are added.
enum Palette {
    static let paper = Color(red: 0xF7 / 255, green: 0xF2 / 255, blue: 0xEC / 255) // #f7f2ec
    static let paperAlt = Color(red: 0xF4 / 255, green: 0xEE / 255, blue: 0xE5 / 255) // #f4eee5
    static let ink = Color(red: 0x3B / 255, green: 0x33 / 255, blue: 0x40 / 255) // #3b3340
    static let inkSoft = Color(red: 0x5E / 255, green: 0x58 / 255, blue: 0x62 / 255) // #5e5862
    static let muted = Color(red: 0x6B / 255, green: 0x64 / 255, blue: 0x70 / 255) // #6b6470
    static let accent = Color(red: 0xC0 / 255, green: 0x8A / 255, blue: 0x72 / 255) // #c08a72 terracotta
}
