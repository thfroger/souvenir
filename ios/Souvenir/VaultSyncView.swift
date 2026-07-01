import SwiftUI

/// Cross-device vault-key sharing (SECURITY.md §3), framed as care rather than a
/// crypto chore. On the device that holds the souvenirs, the user sets a secret
/// phrase; on another of *her* devices, she types the same phrase to bring the
/// souvenirs back to life. The phrase never leaves the device, and we can never
/// recover it for her (§7).
///
/// Two entry points share one flow:
/// - from Réglages → `.choose` (set up vs. enter)
/// - from the "illisibles" banner → straight to `.recover`
struct VaultSyncView: View {
    @EnvironmentObject private var store: MemoryStore
    let onClose: () -> Void

    @State private var step: Step
    @State private var phrase = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var error: String?
    @State private var doneMessage = ""

    enum Step { case choose, enroll, recover, done }

    init(start: Step = .choose, onClose: @escaping () -> Void) {
        _step = State(initialValue: start)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    topBar
                    switch step {
                    case .choose:  chooseStep
                    case .enroll:  enrollStep
                    case .recover: recoverStep
                    case .done:    doneStep
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Fermer", action: onClose)
                .font(Typo.sans(15, .medium))
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: choose

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("MES APPAREILS")
            Text("Retrouver tes souvenirs sur chacun de tes appareils.")
                .font(Typo.serif(32)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Une **phrase secrète**, connue de toi seule, relie tes appareils. Elle ne quitte jamais l'appareil et nous ne pouvons jamais la retrouver à ta place.")
                .bodyStyle()

            choiceCard(icon: "key", title: "Définir ma phrase",
                       subtitle: "Sur cet appareil, qui contient déjà tes souvenirs.") { step = .enroll }
            choiceCard(icon: "arrow.down.heart", title: "Saisir ma phrase",
                       subtitle: "Pour rouvrir tes souvenirs sur cet appareil-ci.") { step = .recover }
        }
    }

    // MARK: enroll (device holds the key)

    private var enrollStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("DÉFINIR MA PHRASE")
            Text("Choisis une phrase que tu n'oublieras pas.")
                .font(Typo.serif(30)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tu la retaperas sur tes autres appareils pour y retrouver tes souvenirs. Garde-la précieusement : c'est elle qui les protège.")
                .bodyStyle()

            secureField("Ta phrase secrète", text: $phrase)
            secureField("Confirme la phrase", text: $confirm)

            errorLine
            primaryButton(working ? "Un instant…" : "Relier mes appareils",
                          enabled: !working && phrase.count >= 6 && phrase == confirm) {
                Task { await runEnroll() }
            }
            Text("MINIMUM 6 CARACTÈRES · LA PHRASE NE QUITTE JAMAIS CET APPAREIL")
                .font(Typo.mono(9)).tracking(1).foregroundStyle(Palette.muted)
        }
    }

    // MARK: recover (device needs the key)

    private var recoverStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("SAISIR MA PHRASE")
            Text("Rouvrir tes souvenirs ici.")
                .font(Typo.serif(32)).foregroundStyle(Palette.ink)
            Text("Tape la phrase secrète définie sur ton autre appareil. Elle déverrouille la clé de ton coffre, puis disparaît.")
                .bodyStyle()

            secureField("Ta phrase secrète", text: $phrase)

            errorLine
            primaryButton(working ? "Déverrouillage…" : "Retrouver mes souvenirs",
                          enabled: !working && !phrase.isEmpty) {
                Task { await runRecover() }
            }
        }
    }

    // MARK: done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("C'EST FAIT")
            Text(doneMessage)
                .font(Typo.serif(30)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton("Terminer", enabled: true, action: onClose)
        }
    }

    // MARK: actions

    private func runEnroll() async {
        working = true; error = nil
        defer { working = false }
        switch await store.enrollPassphrase(phrase) {
        case .success:
            doneMessage = "Tes appareils sont reliés. Saisis cette phrase sur un autre pour y retrouver tes souvenirs."
            step = .done
        case .noKey:
            error = "Cet appareil n'a pas encore la clé du coffre — utilise plutôt « Saisir ma phrase »."
        case .offline:
            error = "Impossible de joindre le coffre. Vérifie ta connexion et réessaie."
        case .failed:
            error = "Quelque chose a coincé. Réessaie."
        }
    }

    private func runRecover() async {
        working = true; error = nil
        defer { working = false }
        switch await store.recoverWithPassphrase(phrase) {
        case .success(let readable):
            doneMessage = readable > 0
                ? "Tes souvenirs sont de retour — \(readable) déjà lisible\(readable > 1 ? "s" : "") sur cet appareil."
                : "Clé adoptée. Tes souvenirs vont réapparaître à mesure qu'ils se synchronisent."
            step = .done
        case .wrongPassphrase:
            error = "Cette phrase ne correspond pas. Réessaie."
        case .noBundle:
            error = "Aucune phrase n'a encore été définie. Fais-le d'abord sur l'appareil qui contient tes souvenirs."
        case .offline:
            error = "Impossible de joindre le coffre. Vérifie ta connexion et réessaie."
        case .failed:
            error = "Le déverrouillage a échoué. Réessaie."
        }
    }

    // MARK: components

    @ViewBuilder private var errorLine: some View {
        if let error {
            Text(error)
                .font(Typo.sans(13.5))
                .foregroundStyle(Color(red: 0.62, green: 0.26, blue: 0.22))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func monoLabel(_ text: String) -> some View {
        Text(text).font(Typo.mono(11)).tracking(2).foregroundStyle(Palette.muted)
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "lock").foregroundStyle(Palette.accent).frame(width: 22)
            SecureField(placeholder, text: text)
                .font(Typo.sans(16)).foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.paperAlt, lineWidth: 1))
    }

    private func choiceCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typo.sans(16, .medium)).foregroundStyle(Palette.ink)
                    Text(subtitle).font(Typo.sans(13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.paperAlt, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.sans(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Palette.ink : Palette.muted, in: RoundedRectangle(cornerRadius: 100))
        }
        .disabled(!enabled)
        .padding(.top, 4)
    }
}

private extension Text {
    func bodyStyle() -> some View {
        self.font(Typo.sans(16))
            .foregroundStyle(Palette.inkSoft)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VaultSyncView(onClose: {})
        .environmentObject(MemoryStore())
}
