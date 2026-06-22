import SwiftUI

/// Skeleton entry view. The joyful core (Frise / Arbre / Immersif / Ajout —
/// DESIGN_INTEGRATION.md §11) and the Réglages hub + security-critical screens
/// (§9) are still to build. The crypto core stays isolated (SECURITY.md §1.5);
/// this UI is deliberately thin.
struct ContentView: View {
    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            VStack(spacing: 14) {
                Text(todayLabel)
                    .font(.system(.caption, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Palette.muted)

                Text("Souvenir")
                    .font(.system(size: 56, design: .serif))
                    .foregroundStyle(Palette.ink)

                Text("squelette — UI fine sur un cœur crypto isolé")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)

                Label("cœur crypto branché : à venir (libsodium iOS)", systemImage: "lock.shield")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 8)
            }
            .padding(32)
        }
    }
}

#Preview {
    ContentView()
}
