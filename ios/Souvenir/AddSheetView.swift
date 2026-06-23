import SwiftUI

/// Feuille d'ajout (écran D, modale) — DESIGN.md §3.D.
/// V1 picks only the TYPE of memory: no perso/partagé choice (that's V2,
/// DESIGN_INTEGRATION.md §0/§7). Picking a tile reports the kind; text types
/// (citation/mesure) lead to capture, media types come next.
struct AddSheetView: View {
    let childName: String
    let onPick: (MemoryKind) -> Void

    private struct Tile: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let color: Color
        let kind: MemoryKind
    }

    private let tiles: [Tile] = [
        Tile(label: "Photo", icon: "camera", color: Palette.bleu, kind: .photo),
        Tile(label: "Note vocale", icon: "mic", color: Palette.peche, kind: .voice),
        Tile(label: "Citation", icon: "text.quote", color: Palette.lilas, kind: .citation),
        Tile(label: "Jalon", icon: "leaf", color: Palette.vert, kind: .milestone),
        Tile(label: "Mesure", icon: "ruler", color: Palette.jaune, kind: .measure),
        Tile(label: "Dessin", icon: "scribble.variable", color: Palette.rose, kind: .drawing),
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
                    .font(Typo.serif(24))
                    .foregroundStyle(Palette.ink)
                Text("de \(childName) — aujourd'hui")
                    .font(Typo.mono(14))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { t in
                    Button { onPick(t.kind) } label: { tile(t) }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)

            Spacer(minLength: 0)
        }
    }

    private func tile(_ t: Tile) -> some View {
        VStack(spacing: 10) {
            Image(systemName: t.icon)
                .font(.system(size: 24))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(t.color)
            Text(t.label)
                .font(Typo.sans(13))
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
        AddSheetView(childName: "Léa") { _ in }
            .presentationDetents([.height(380)])
            .presentationBackground(Palette.paper)
    }
}
