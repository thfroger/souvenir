import SwiftUI

/// Réglages hub (DESIGN_INTEGRATION.md §9). The header's sliders button opens
/// this; from here a tender, real V1 destination — social recovery — and, in
/// DEBUG builds only, the dev server address so a physical iPhone can reach the
/// Mac's backend over the LAN. The server section never ships in a signed build.
struct SettingsView: View {
    @EnvironmentObject private var store: MemoryStore
    let childName: String
    let onClose: () -> Void

    @State private var showRecovery = false
    @State private var showSync = false

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    topBar
                    title
                    syncRow
                    recoveryRow
                    #if DEBUG
                    DebugSeasonSection()
                    ServerSettingsSection()
                        .environmentObject(store)
                    #endif
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showRecovery) {
            SocialRecoveryView(childName: childName, store: store) { showRecovery = false }
        }
        .sheet(isPresented: $showSync) {
            VaultSyncView { showSync = false }
                .environmentObject(store)
        }
    }

    private var syncRow: some View {
        Button { showSync = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mes appareils")
                        .font(Typo.sans(16, .medium))
                        .foregroundStyle(Palette.ink)
                    Text("Une phrase secrète pour retrouver tes souvenirs partout.")
                        .font(Typo.sans(13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.paperAlt, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Fermer", action: onClose)
                .font(Typo.sans(15, .medium))
                .foregroundStyle(Palette.muted)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RÉGLAGES")
                .font(Typo.mono(11))
                .tracking(2)
                .foregroundStyle(Palette.muted)
            Text("Prendre soin de l'essentiel")
                .font(Typo.serif(32))
                .foregroundStyle(Palette.ink)
        }
    }

    private var recoveryRow: some View {
        Button { showRecovery = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Récupération sociale")
                        .font(Typo.sans(16, .medium))
                        .foregroundStyle(Palette.ink)
                    Text("Un filet de proches, au cas où.")
                        .font(Typo.sans(13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.paperAlt, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// DEBUG-only: force the Ciel season to tune density/speed without waiting for the
/// calendar. "Auto" follows the real date. Persisted in UserDefaults; ArbreView
/// reads the same key via @AppStorage.
private struct DebugSeasonSection: View {
    @AppStorage("debugSeason") private var debugSeason = "auto"

    private let options: [(value: String, label: String)] = [
        ("auto", "Auto (date du jour)"),
        ("spring", "Printemps"),
        ("summer", "Été"),
        ("autumn", "Automne"),
        ("winter", "Hiver"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SAISON · DÉVELOPPEMENT")
                .font(Typo.mono(11)).tracking(2).foregroundStyle(Palette.muted)

            Text("Forcer la saison de l'écran Ciel pour régler densité et vitesse. « Auto » suit la vraie date.")
                .font(Typo.sans(14)).foregroundStyle(Palette.inkSoft)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)

            Menu {
                ForEach(options, id: \.value) { opt in
                    Button(opt.label) { debugSeason = opt.value }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "leaf").foregroundStyle(Palette.accent).frame(width: 22)
                    Text(options.first { $0.value == debugSeason }?.label ?? "Auto (date du jour)")
                        .font(Typo.sans(16)).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.paperAlt, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Palette.paperAlt, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// DEBUG-only: point the app at the Mac's LAN IP so a physical iPhone can sync
/// against the dev backend (`localhost` on the phone is the phone itself). Holds
/// only a server address — never a secret or any child data.
private struct ServerSettingsSection: View {
    @EnvironmentObject private var store: MemoryStore
    @State private var text = BackendConfig.overrideText ?? ""
    @State private var saved = false

    private var preview: URL? { BackendConfig.normalized(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SERVEUR · DÉVELOPPEMENT")
                .font(Typo.mono(11))
                .tracking(2)
                .foregroundStyle(Palette.muted)

            Text("Sur iPhone, `localhost` désigne le téléphone. Pour synchroniser avec le backend du Mac, saisis son IP locale (ex. **192.168.1.20**). Vide = retour à localhost.")
                .font(Typo.sans(14))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Image(systemName: "network").foregroundStyle(Palette.accent).frame(width: 22)
                TextField("192.168.1.20", text: $text)
                    .font(Typo.mono(15))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: text) { saved = false }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.paperAlt, lineWidth: 1))

            Text(statusLine)
                .font(Typo.mono(11))
                .foregroundStyle(saved ? Palette.accent : Palette.muted)

            Button {
                BackendConfig.setOverride(text)
                store.reconnect()
                saved = true
            } label: {
                Text(buttonLabel)
                    .font(Typo.sans(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(buttonBackground, in: RoundedRectangle(cornerRadius: 100))
            }
        }
        .padding(18)
        .background(Palette.paperAlt, in: RoundedRectangle(cornerRadius: 20))
    }

    private var statusLine: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "→ localhost:8787 (défaut simulateur)" }
        if let url = preview { return "→ \(url.absoluteString)" }
        return "adresse non valide"
    }

    // The button must report the real reconnect result — not optimistically claim
    // success — so the on-device sync test actually means something.
    private var buttonLabel: String {
        guard saved else { return "Enregistrer et reconnecter" }
        switch store.connState {
        case .connecting: return "Connexion…"
        case .connected:  return "Connecté ✓"
        case .failed:     return "Hors ligne — réessayer"
        case .idle:       return "Enregistrer et reconnecter"
        }
    }

    private var buttonBackground: Color {
        guard saved else { return Palette.ink }
        switch store.connState {
        case .failed: return Color(red: 0.62, green: 0.26, blue: 0.22) // brick: honest failure
        default:      return Palette.ink
        }
    }
}
#endif

#Preview {
    SettingsView(childName: "Léa", onClose: {})
        .environmentObject(MemoryStore())
}
