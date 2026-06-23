import SwiftUI

/// Feuille d'ajout (écran D, modale) — DESIGN.md §3.D.
/// V1 picks only the TYPE of memory: no perso/partagé choice (that's V2,
/// DESIGN_INTEGRATION.md §0/§7). Tiles currently just dismiss; they'll route to
/// the real capture flows later.
struct AddSheetView: View {
    let childName: String
    let onClose: () -> Void

    private struct Kind: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let color: Color
    }

    private let kinds: [Kind] = [
        Kind(label: "Photo", icon: "camera", color: Palette.bleu),
        Kind(label: "Note vocale", icon: "mic", color: Palette.peche),
        Kind(label: "Citation", icon: "text.quote", color: Palette.lilas),
        Kind(label: "Jalon", icon: "leaf", color: Palette.vert),
        Kind(label: "Mesure", icon: "ruler", color: Palette.jaune),
        Kind(label: "Dessin", icon: "scribble.variable", color: Palette.rose),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Palette.divider)
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("Garder un souvenir")
                    .font(.system(size: 24, design: .serif))
                    .foregroundStyle(Palette.ink)
                Text("de \(childName) — aujourd'hui")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(kinds) { kind in
                    Button { onClose() } label: { tile(kind) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)

            Spacer(minLength: 0)
        }
    }

    private func tile(_ kind: Kind) -> some View {
        VStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 24))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(kind.color)
            Text(kind.label)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: 0x50323C).opacity(0.06), radius: 5, y: 2)
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        AddSheetView(childName: "Léa", onClose: {})
            .presentationDetents([.height(380)])
            .presentationBackground(Palette.paper)
    }
}
