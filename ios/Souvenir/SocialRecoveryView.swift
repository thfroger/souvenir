import SwiftUI

/// Social-recovery setup (SECURITY.md §5 / DESIGN_INTEGRATION.md §9), framed as
/// an act of care rather than a cryptographic chore. Three tender steps:
/// intro → choose three guardians → the net is woven.
struct SocialRecoveryView: View {
    @StateObject private var model: RecoverySetupModel
    @State private var step: Step = .intro
    let onFinish: () -> Void

    enum Step { case intro, guardians, sealed }

    init(childName: String, onFinish: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RecoverySetupModel(childName: childName))
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    switch step {
                    case .intro: intro
                    case .guardians: guardiansStep
                    case .sealed: sealedStep
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    // MARK: Step 1 — intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("RÉCUPÉRATION SOCIALE")
            Text("Un filet pour les souvenirs de \(model.childName).")
                .font(Typo.serif(34))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Si tu perdais tous tes appareils, **deux personnes de confiance** suffiraient à te rouvrir la porte — jamais une seule, et jamais nous.")
                .bodyStyle()

            careCard(
                icon: "leaf",
                "Choisis des proches en dehors de tes éventuels conflits — quelqu'un qui restera dans ta vie quoi qu'il arrive."
            )

            primaryButton("Choisir les gardiens") { step = .guardians }
        }
    }

    // MARK: Step 2 — choose guardians

    private var guardiansStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("TROIS GARDIENS · DEUX SUFFISENT")
            Text("Qui veillera sur ces souvenirs ?")
                .font(Typo.serif(30))
                .foregroundStyle(Palette.ink)

            VStack(spacing: 12) {
                ForEach($model.guardians) { $guardian in
                    guardianRow($guardian)
                }
            }

            Text("Deux d'entre eux, ensemble, pourront t'aider à revenir. Aucun ne peut rien faire seul.")
                .font(Typo.sans(13))
                .foregroundStyle(Palette.muted)

            if let error = model.errorMessage {
                Text(error).font(Typo.sans(13)).foregroundStyle(.red)
            }

            primaryButton("Tisser le filet", enabled: model.canSeal) {
                model.seal()
                if model.isSealed { step = .sealed }
            }
        }
    }

    private func guardianRow(_ guardian: Binding<RecoverySetupModel.Guardian>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person")
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            TextField("Prénom d'un proche", text: guardian.name)
                .font(Typo.sans(16))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.paperAlt, lineWidth: 1))
    }

    // MARK: Step 3 — sealed

    private var sealedStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            monoLabel("LE FILET EST TISSÉ")
            Text("C'est en sécurité.")
                .font(Typo.serif(34))
                .foregroundStyle(Palette.ink)

            Text("\(sentenceList(model.trimmedNames)) veillent désormais. Chacun reçoit une part qui, seule, ne révèle rien.")
                .bodyStyle()

            VStack(spacing: 10) {
                ForEach(model.trimmedNames, id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(Palette.accent)
                        Text(name).font(Typo.sans(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("part prête")
                            .font(Typo.mono(11))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }

            Text("AUCUNE PART NE QUITTE CET APPAREIL EN CLAIR · 2 SUR 3 SUFFISENT · NOUS NE POUVONS JAMAIS RÉCUPÉRER À TA PLACE")
                .font(Typo.mono(9))
                .tracking(1)
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)

            primaryButton("Terminer", action: onFinish)
        }
    }

    // MARK: components

    private func monoLabel(_ text: String) -> some View {
        Text(text)
            .font(Typo.mono(11))
            .tracking(2)
            .foregroundStyle(Palette.muted)
    }

    private func careCard(icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.accent)
            Text(text).font(Typo.sans(15)).foregroundStyle(Palette.inkSoft)
        }
        .padding(16)
        .background(Palette.paperAlt, in: RoundedRectangle(cornerRadius: 18))
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.sans(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Palette.ink : Palette.muted, in: RoundedRectangle(cornerRadius: 100))
        }
        .disabled(!enabled)
        .padding(.top, 8)
    }

    private func sentenceList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " et " + names.last!
        }
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
    SocialRecoveryView(childName: "Léa", onFinish: {})
}
