import SwiftUI

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

// Design tokens from DESIGN.md §2 / README.md (paper-cream editorial palette).
// Instrument Serif / Hanken / Geist Mono are not bundled yet → system fallbacks
// (.serif / .default / .monospaced) until the real fonts are added.
enum Palette {
    static let paper = Color(hex: 0xF7F2EC)
    static let paperAlt = Color(hex: 0xF4EEE5)
    static let ink = Color(hex: 0x3B3340)
    static let inkSoft = Color(hex: 0x5E5862)
    static let muted = Color(hex: 0x6B6470)
    static let faint = Color(hex: 0x9A9088)
    static let accent = Color(hex: 0xC08A72) // terracotta
    static let chip = Color(hex: 0xECE4D8)
    static let divider = Color(hex: 0xE2D8C9)

    // Pastels souvenirs (DESIGN.md §2).
    static let rose = Color(hex: 0xF1C8D4)
    static let lilas = Color(hex: 0xC9C2EE)
    static let bleu = Color(hex: 0xBCD6EE)
    static let vert = Color(hex: 0xC4DDCB)
    static let jaune = Color(hex: 0xF0DFAE)
    static let peche = Color(hex: 0xF4CDB6)
}
