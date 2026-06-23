import SwiftUI
import CoreText

/// Registers the bundled fonts at launch (no UIAppFonts needed with a generated
/// Info.plist) and exposes the design's three families (DESIGN.md §2):
/// Instrument Serif (titles), Hanken Grotesk (UI/body), Geist Mono (metadata).
enum Fonts {
    static func register() {
        for name in ["InstrumentSerif-Regular", "InstrumentSerif-Italic",
                     "HankenGrotesk-Variable", "GeistMono-Variable"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum Typo {
    static func serif(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Italic", size: size) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("HankenGrotesk-Regular", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Regular", size: size) }
}
