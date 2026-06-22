import SwiftUI
import CryptoCore

/// Skeleton entry view. The joyful core (Frise / Arbre / Immersif / Ajout —
/// DESIGN_INTEGRATION.md §11) and the Réglages hub + security-critical screens
/// (§9) are still to build. The crypto core stays isolated (SECURITY.md §1.5);
/// this UI is deliberately thin — here it just runs a live self-check through
/// `CryptoCore` to prove the wiring end-to-end.
struct ContentView: View {
    @State private var cryptoStatus: SelfCheck = .running
    @State private var showRecovery = false

    enum SelfCheck {
        case running, ok, failed(String)
    }

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

                statusLabel
                    .font(.footnote.monospaced())
                    .padding(.top, 8)

                Button("Configurer la récupération") { showRecovery = true }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)
            }
            .padding(32)
        }
        .task { cryptoStatus = Self.runSelfCheck() }
        .sheet(isPresented: $showRecovery) {
            SocialRecoveryView(childName: "Léa") { showRecovery = false }
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch cryptoStatus {
        case .running:
            Label("self-check du cœur crypto…", systemImage: "hourglass")
                .foregroundStyle(Palette.muted)
        case .ok:
            Label("cœur crypto vérifié (round-trip + emballage)", systemImage: "checkmark.shield.fill")
                .foregroundStyle(Palette.accent)
        case .failed(let why):
            Label("self-check échoué : \(why)", systemImage: "xmark.shield")
                .foregroundStyle(.red)
        }
    }

    /// Runs a real encrypt→decrypt round-trip and a key-wrap round-trip through
    /// CryptoCore (the same primitives as TESTING.md §1).
    static func runSelfCheck() -> SelfCheck {
        do {
            let key = try SymmetricKey.generate()
            let message = Array("self-check".utf8)
            let opened = try AEAD.open(try AEAD.seal(message, key: key.bytes), key: key.bytes)

            let dek = try DataKey.generate()
            let vk = try VaultKey.generate()
            let dek2 = try KeyWrap.unwrap(try KeyWrap.wrap(dek, under: vk), with: vk)

            guard opened == message, dek2 == dek else {
                return .failed("résultat inattendu")
            }
            return .ok
        } catch {
            return .failed("\(error)")
        }
    }
}

#Preview {
    ContentView()
}
