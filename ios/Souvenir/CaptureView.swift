import SwiftUI

/// Text capture for the types that need no media/permissions yet: Citation and
/// Mesure. On save, the content is encrypted through the store (CryptoCore) and
/// appears in the Frise. Photo / Note vocale / Jalon / Dessin come next.
struct CaptureView: View {
    let kind: MemoryKind
    let childID: UUID
    let childName: String
    let onClose: () -> Void

    @EnvironmentObject private var store: MemoryStore
    @State private var text = ""
    @State private var title = ""
    @FocusState private var focused: Bool

    private var heading: String { kind == .citation ? "Une petite phrase" : "Une mesure" }
    private var prompt: String { kind == .citation ? "« ce qu'iel a dit »" : "ex. 78 cm" }

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(heading)
                        .font(Typo.serif(30))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 34, height: 34)
                            .background(Palette.chip, in: Circle())
                    }
                }

                Text("DE \(childName.uppercased()) — AUJOURD'HUI")
                    .font(Typo.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Palette.faint)

                TextField(prompt, text: $text, axis: .vertical)
                    .font(kind == .citation ? Typo.serif(22) : Typo.sans(20))
                    .foregroundStyle(Palette.ink)
                    .focused($focused)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.divider, lineWidth: 1))

                if kind == .citation {
                    TextField("Titre (optionnel)", text: $title)
                        .font(Typo.sans(15))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()

                Button(action: save) {
                    Text("Garder ce souvenir")
                        .font(Typo.sans(17, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Palette.ink : Palette.muted, in: RoundedRectangle(cornerRadius: 100))
                }
                .disabled(!canSave)
            }
            .padding(28)
        }
        .onAppear { focused = true }
    }

    private func save() {
        switch kind {
        case .citation: store.addCitation(childID: childID, quote: text, title: title)
        case .measure: store.addMeasure(childID: childID, value: text)
        default: break
        }
        onClose()
    }
}
