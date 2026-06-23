import SwiftUI

/// Écran B — a living seasonal scene where the child's memories take the form of
/// the season and move across the screen: flowers growing (printemps), fish
/// swimming (été), leaves fluttering down (automne), snow falling (hiver). Each
/// element is a real decrypted memory and opens immersively on tap.
///
/// Pure client-side rendering (DESIGN_INTEGRATION §3); no content leaves the device.
struct ArbreView: View {
    let childID: UUID
    @EnvironmentObject private var store: MemoryStore
    @State private var openedMemory: Memory?
    @State private var start = Date()

    private var child: Child { SampleData.children.first { $0.id == childID } ?? SampleData.lea }
    private var season: Season { Season.current() }

    private var memories: [Memory] {
        let all = store.memories(for: child)
        return Array((all.isEmpty ? SampleData.memories(for: child) : all).prefix(18))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [season.tint.opacity(0.30), Palette.paper],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                scene
                statCards
                Color.clear.frame(height: 84)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
        }
        .fullScreenCover(item: $openedMemory) { memory in
            ImmersiveMemoryView(memory: memory, child: child) { openedMemory = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(season.place)
                .font(Typo.mono(11)).tracking(3).foregroundStyle(Palette.muted)
            Text(child.name)
                .font(Typo.serif(32)).foregroundStyle(Palette.ink)
            Text(season.label)
                .font(Typo.mono(10)).tracking(2).foregroundStyle(Palette.faint)
        }
    }

    private var scene: some View {
        let mems = memories // decrypt once per render, not per animation frame
        return GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                ZStack {
                    ForEach(Array(mems.enumerated()), id: \.element.id) { i, mem in
                        element(mem, index: i, count: mems.count, t: t, size: geo.size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func element(_ mem: Memory, index: Int, count: Int, t: Double, size: CGSize) -> some View {
        let r = Seed(mem.id)
        let color = season.palette[r.idx(9, season.palette.count)]
        switch season {
        case .summer: fish(mem, r, index, count, t, size, color)
        case .autumn: faller(mem, r, index, count, t, size, color, snow: false)
        case .winter: faller(mem, r, index, count, t, size, color, snow: true)
        case .spring: flower(mem, r, index, count, t, size, color)
        }
    }

    // ÉTÉ — fish swimming across the screen in vertical lanes, gently bobbing.
    @ViewBuilder
    private func fish(_ mem: Memory, _ r: Seed, _ i: Int, _ n: Int, _ t: Double, _ s: CGSize, _ c: Color) -> some View {
        let lane = (Double(i) + 0.5) / Double(max(1, n))
        let baseY = 40 + CGFloat(lane) * max(1, s.height - 80)
        let dir: CGFloat = r.v(2) < 0.5 ? 1 : -1
        let period = 9 + r.v(3) * 6
        let prog = ((t / period) + r.v(4)).truncatingRemainder(dividingBy: 1)
        let span = s.width + 160
        let x = dir > 0 ? -80 + CGFloat(prog) * span : s.width + 80 - CGFloat(prog) * span
        let y = baseY + CGFloat(sin(t * (0.7 + r.v(5) * 0.6) + r.v(6) * 6) * 16)
        node(mem, x: x, y: y, opacity: edgeFade(prog)) {
            Image(systemName: "fish.fill")
                .font(.system(size: 22 + r.v(7) * 10))
                .foregroundStyle(c)
                .scaleEffect(x: dir, y: 1)
                .shadow(color: c.opacity(0.4), radius: 6)
        }
    }

    // AUTOMNE / HIVER — leaves flutter or snow drifts from top to bottom, swaying
    // and rotating as they fall.
    @ViewBuilder
    private func faller(_ mem: Memory, _ r: Seed, _ i: Int, _ n: Int, _ t: Double, _ s: CGSize, _ c: Color, snow: Bool) -> some View {
        let period = snow ? 13 + r.v(2) * 9 : 7 + r.v(2) * 6
        let prog = ((t / period) + r.v(3)).truncatingRemainder(dividingBy: 1)
        let y = -60 + CGFloat(prog) * (s.height + 120)
        let swaySpeed = (snow ? 0.6 : 0.9) + r.v(4) * 0.6
        let swayAmp = snow ? 14 + r.v(6) * 14 : 24 + r.v(6) * 26
        let baseX = 30 + CGFloat(r.v(7)) * max(1, s.width - 60)
        let x = baseX + CGFloat(sin(t * swaySpeed + r.v(5) * 6) * swayAmp)
        let rot = sin(t * ((snow ? 0.5 : 1.1) + r.v(8)) + r.v(5) * 6) * (snow ? 60 : 70)
        node(mem, x: x, y: y, opacity: edgeFade(prog)) {
            Image(systemName: snow ? "snowflake" : "leaf.fill")
                .font(.system(size: snow ? 18 + r.v(7) * 8 : 20 + r.v(7) * 10))
                .foregroundStyle(c)
                .rotationEffect(.degrees(rot))
                .shadow(color: c.opacity(0.3), radius: 4)
        }
    }

    // PRINTEMPS — flowers grow up from their spot, bloom, then fade as others
    // sprout. Rooted on a jittered grid so they don't pile up.
    @ViewBuilder
    private func flower(_ mem: Memory, _ r: Seed, _ i: Int, _ n: Int, _ t: Double, _ s: CGSize, _ c: Color) -> some View {
        let cols = n <= 8 ? 2 : 3
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let cellW = s.width / CGFloat(cols)
        let cellH = s.height / CGFloat(rows)
        let x = (CGFloat(i % cols) + 0.5) * cellW + (CGFloat(r.v(3)) - 0.5) * cellW * 0.4
        let y = (CGFloat(i / cols) + 0.5) * cellH + (CGFloat(r.v(4)) - 0.5) * cellH * 0.4
        let period = 11 + r.v(2) * 7
        let local = ((t / period) + Double(i) / Double(max(1, n))).truncatingRemainder(dividingBy: 1)
        let grow = smoothstep(0, 0.28, local)               // sprout
        let scale = grow * (1 - smoothstep(0.82, 1, local))  // bloom then fade away
        let op = min(grow, 1 - smoothstep(0.86, 1, local))
        node(mem, x: x, y: y, opacity: op) {
            FlowerGlyph(petal: c)
                .scaleEffect(scale, anchor: .bottom)
        }
    }

    // A tappable souvenir: its seasonal glyph + a faint title that fades with it.
    private func node(_ mem: Memory, x: CGFloat, y: CGFloat, opacity: Double,
                      @ViewBuilder glyph: () -> some View) -> some View {
        Button { openedMemory = mem } label: {
            VStack(spacing: 4) {
                glyph()
                Text(mem.title)
                    .font(Typo.serif(11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .position(x: x, y: y)
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
            Text(label).font(Typo.mono(11)).tracking(1.5).foregroundStyle(Palette.muted)
            Text(value).font(Typo.serif(26)).foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x50323C).opacity(0.08), radius: 6, y: 3)
    }
}

extension SampleData {
    /// Tree stats — computed client-side from decrypted memories (DESIGN_INTEGRATION §3);
    /// here placeholder totals. Height is the latest decrypted "Mesure" (§4).
    static func treeStats(for child: Child) -> (height: String, sparks: Int) {
        child.id == noe.id ? ("71 cm", 58) : ("78 cm", 142)
    }
}

/// A small drawn flower (no emoji): petals around a yellow heart, growing from
/// its base.
private struct FlowerGlyph: View {
    let petal: Color
    var body: some View {
        ZStack {
            ForEach(0..<6) { i in
                Capsule().fill(petal)
                    .frame(width: 8, height: 16)
                    .offset(y: -8)
                    .rotationEffect(.degrees(Double(i) / 6 * 360))
            }
            Circle().fill(Palette.jaune).frame(width: 8, height: 8)
        }
        .frame(width: 30, height: 30)
        .shadow(color: petal.opacity(0.35), radius: 5)
    }
}

// Fade in/out near the start/end of a 0…1 progress so elements don't pop at edges.
private func edgeFade(_ p: Double) -> Double {
    smoothstep(0, 0.07, p) * (1 - smoothstep(0.93, 1, p))
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

// Deterministic per-memory pseudo-random values (stable within a session).
private struct Seed {
    let id: UUID
    init(_ id: UUID) { self.id = id }
    func v(_ salt: Int) -> Double {
        var h = Hasher(); h.combine(id); h.combine(salt)
        return Double(UInt64(bitPattern: Int64(h.finalize())) % 100_000) / 100_000.0
    }
    func idx(_ salt: Int, _ mod: Int) -> Int { Int(v(salt) * Double(mod)) % max(1, mod) }
}

enum Season {
    case spring, summer, autumn, winter

    static func current(_ date: Date = Date()) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    var place: String {
        switch self {
        case .spring: return "LE JARDIN DE"
        case .summer: return "L'OCÉAN DE"
        case .autumn: return "LA FORÊT DE"
        case .winter: return "LA NEIGE DE"
        }
    }

    var label: String {
        switch self {
        case .spring: return "PRINTEMPS"
        case .summer: return "ÉTÉ"
        case .autumn: return "AUTOMNE"
        case .winter: return "HIVER"
        }
    }

    var palette: [Color] {
        switch self {
        case .spring: return [Palette.rose, Palette.lilas, Palette.jaune, Palette.peche]
        case .summer: return [Palette.accent, Palette.peche, Palette.jaune, Color(hex: 0xE08A4C)]
        case .autumn: return [Palette.accent, Palette.peche, Palette.jaune, Color(hex: 0xC9762F)]
        case .winter: return [Palette.bleu, Palette.lilas, Color(hex: 0x9FB4C7), Color(hex: 0xBFD3E6)]
        }
    }

    var tint: Color {
        switch self {
        case .spring: return Palette.vert
        case .summer: return Palette.bleu
        case .autumn: return Palette.accent
        case .winter: return Palette.bleu
        }
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id)
}
