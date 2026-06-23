import SwiftUI

// Milestone shown on the tree. Linked to a memory (opens immersively).
struct Milestone: Identifiable {
    var id: UUID { memory.id }
    let label: String
    let ageLabel: String
    let ring: Color
    let dx: CGFloat
    let dy: CGFloat
    let active: Bool
    let memory: Memory
}

extension SampleData {
    static func milestones(for child: Child) -> [Milestone] {
        func m(_ title: String, _ days: Int, _ p: [Color]) -> Memory {
            Memory(childID: child.id, kind: .milestone, daysAgo: days, title: title, note: nil, audio: nil, pastel: p)
        }
        if child.id == noe.id {
            return [
                Milestone(label: "Premier sourire", ageLabel: "3 MOIS", ring: Palette.peche, dx: -78, dy: -40, active: false, memory: m("Premier sourire", 120, [Palette.peche, Palette.jaune])),
                Milestone(label: "Première nuit complète", ageLabel: "6 MOIS", ring: Palette.accent, dx: 40, dy: -150, active: true, memory: m("Première nuit complète", 40, [Palette.lilas, Palette.bleu])),
            ]
        }
        return [
            Milestone(label: "Premier sourire", ageLabel: "2 MOIS", ring: Palette.peche, dx: -92, dy: -52, active: false, memory: m("Premier sourire", 900, [Palette.peche, Palette.jaune])),
            Milestone(label: "Premiers pas", ageLabel: "13 MOIS", ring: Palette.vert, dx: 78, dy: -168, active: false, memory: m("Premiers pas", 500, [Palette.vert, Palette.jaune])),
            Milestone(label: "Première dent", ageLabel: "3 ANS", ring: Palette.accent, dx: -24, dy: -120, active: true, memory: m("Première dent", 4, [Palette.vert, Palette.jaune])),
        ]
    }

    /// Tree stats — computed client-side from decrypted memories (DESIGN_INTEGRATION §3);
    /// here placeholder totals. Height is the latest decrypted "Mesure" (§4).
    static func treeStats(for child: Child) -> (height: String, sparks: Int) {
        child.id == noe.id ? ("71 cm", 58) : ("78 cm", 142)
    }
}

/// Arbre (level 1) — DESIGN.md §3.C: a living, per-child view of growth;
/// flowering milestones + stats. Background gradient paper-alt → paper.
struct ArbreView: View {
    let childID: UUID
    @EnvironmentObject private var store: MemoryStore
    @State private var openedMemory: Memory?

    private var child: Child { SampleData.children.first { $0.id == childID } ?? SampleData.lea }

    // Captured jalons bloom on the tree (most recent highlighted). They are placed
    // on canopy slots since a captured milestone has no hand-authored position.
    // If none captured yet, keep the decorative samples so the tree isn't bare.
    private var milestones: [Milestone] {
        let captured = store.memories(for: child)
            .filter { $0.kind == .milestone }
            .sorted { $0.date > $1.date }
        guard !captured.isEmpty else { return SampleData.milestones(for: child) }

        let slots: [(CGFloat, CGFloat)] = [
            (-24, -120), (78, -168), (-92, -52), (40, -150), (-78, -40), (34, -188), (92, -96), (-64, -150),
        ]
        let rings: [Color] = [Palette.accent, Palette.vert, Palette.peche, Palette.lilas, Palette.bleu, Palette.jaune]
        return captured.enumerated().map { i, mem in
            let slot = slots[i % slots.count]
            return Milestone(label: mem.title, ageLabel: ageLabel(for: mem),
                             ring: rings[i % rings.count], dx: slot.0, dy: slot.1,
                             active: i == 0, memory: mem)
        }
    }

    private func ageLabel(for mem: Memory) -> String {
        let memYear = Calendar.current.component(.year, from: mem.date)
        let years = max(0, memYear - child.birthYear)
        if years <= 0 { return "BÉBÉ" }
        return "\(years) AN" + (years > 1 ? "S" : "")
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.paperAlt, Palette.paper], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    title
                    treeWithMilestones
                    statCards
                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
            }
        }
        .fullScreenCover(item: $openedMemory) { memory in
            ImmersiveMemoryView(memory: memory, child: child) { openedMemory = nil }
        }
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("L'ARBRE DE")
                .font(Typo.mono(11))
                .tracking(3)
                .foregroundStyle(Palette.muted)
            Text(child.name)
                .font(Typo.serif(32))
                .foregroundStyle(Palette.ink)
        }
    }

    private var treeWithMilestones: some View {
        ZStack {
            TreeView()
            ForEach(milestones) { m in
                Button { openedMemory = m.memory } label: { dot(m) }
                    .buttonStyle(.plain)
                    .offset(x: m.dx, y: m.dy)
            }
            if let active = milestones.first(where: { $0.active }) {
                activeLabel(active)
                    .offset(x: active.dx + 92, y: active.dy)
            }
        }
        .frame(width: 300, height: 400)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func dot(_ m: Milestone) -> some View {
        if m.active {
            Circle().fill(Palette.accent)
                .frame(width: 22, height: 22)
                .shadow(color: Palette.accent.opacity(0.4), radius: 6)
        } else {
            Circle().fill(.white)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(m.ring, lineWidth: 3))
        }
    }

    private func activeLabel(_ m: Milestone) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Palette.accent).frame(width: 16, height: 1.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.ageLabel)
                    .font(Typo.mono(11))
                    .tracking(1)
                    .foregroundStyle(Palette.faint)
                Text(m.label)
                    .font(Typo.serif(15))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: 0x50323C).opacity(0.12), radius: 8, y: 4)
        }
    }

    private var statCards: some View {
        let stats = SampleData.treeStats(for: child)
        return HStack(spacing: 14) {
            statCard("TAILLE", stats.height)
            statCard("SOUVENIRS", "\(stats.sparks) éclats")
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Typo.mono(11))
                .tracking(1.5)
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(Typo.serif(26))
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x50323C).opacity(0.08), radius: 6, y: 3)
    }
}

/// The tree in simple shapes (DESIGN.md §3.C): trunk + two branches + a few
/// overlapping pastel foliage circles (radial gradients).
struct TreeView: View {
    var body: some View {
        ZStack {
            branch(angle: -27)
            branch(angle: 27)

            foliage(Palette.vert, 180, -24, -150)
            foliage(Palette.peche, 150, -82, -108)
            foliage(Palette.lilas, 150, 78, -118)
            foliage(Palette.jaune, 120, 34, -188)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x9C7A5B), Color(hex: 0x6F5237)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 160)
                .offset(y: 110)
        }
        .frame(width: 300, height: 400)
    }

    private func foliage(_ c: Color, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c, c.opacity(0.55)],
                                 center: .init(x: 0.4, y: 0.35), startRadius: 6, endRadius: size / 2))
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    private func branch(angle: Double) -> some View {
        // Pivot at the trunk top (bottom anchor) so the two branches splay into a Y.
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: 0x7E5E45))
            .frame(width: 14, height: 130)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(y: -34)
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id)
}
