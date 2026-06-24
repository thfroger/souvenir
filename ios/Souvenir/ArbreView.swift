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
    @State private var selectedYear: Int? // nil = Toutes

    private var child: Child { SampleData.children.first { $0.id == childID } ?? SampleData.lea }
    private var season: Season { Season.current() }

    private var memories: [Memory] {
        let all = store.memories(for: child)
        return all.isEmpty ? SampleData.memories(for: child) : all
    }

    // The scene shows souvenirs as creatures; a measure is data, not a creature,
    // so it is excluded. Filtered by the chosen year (nil = all years mixed).
    private var filteredMemories: [Memory] {
        let base = memories.filter { $0.kind != .measure }
        guard let y = selectedYear, availableYears.contains(y) else { return base }
        return base.filter { Self.year(of: $0) == y }
    }
    private var sceneMemories: [Memory] { Array(filteredMemories.prefix(24)) }
    private var availableYears: [Int] {
        Array(Set(memories.filter { $0.kind != .measure }.map { Self.year(of: $0) })).sorted(by: >)
    }
    private static func year(of m: Memory) -> Int { Calendar.current.component(.year, from: m.date) }

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
        let mems = sceneMemories // decrypt once per render, not per animation frame
        return GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                ZStack {
                    ambientLayer(t: t, size: geo.size)
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

    // One souvenir's cross/fall/bloom period, drawn from the season's tunable range.
    private func periodFor(_ r: Seed, salt: Int) -> Double {
        let range = season.motion.creaturePeriod
        return range.lowerBound + r.v(salt) * (range.upperBound - range.lowerBound)
    }

    // Decorative seasonal particles behind the souvenirs — they give each season
    // its own density and atmosphere without ever pretending to be a memory (no
    // title, not tappable). Pure index-based: nothing is decrypted here.
    @ViewBuilder
    private func ambientLayer(t: Double, size: CGSize) -> some View {
        let a = season.motion.ambient
        ZStack {
            ForEach(0..<a.count, id: \.self) { i in
                ambientParticle(i, a, t, size)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ambientParticle(_ i: Int, _ a: Season.Ambient, _ t: Double, _ s: CGSize) -> some View {
        let r = AmbientSeed(i)
        let period = a.period.lowerBound + r.v(1) * (a.period.upperBound - a.period.lowerBound)
        let prog = ((t / period) + r.v(2)).truncatingRemainder(dividingBy: 1)
        let glyphSize = a.size.lowerBound + r.v(3) * (a.size.upperBound - a.size.lowerBound)
        let baseX = CGFloat(r.v(4)) * s.width
        let color = season.palette[r.idx(5, season.palette.count)]
        if a.kind.rises {
            // Bubbles drift up from the seabed, swaying faintly.
            let y = s.height + 30 - CGFloat(prog) * (s.height + 60)
            let x = baseX + CGFloat(sin(t * (0.4 + r.v(6) * 0.5) + r.v(7) * 6) * 18)
            Circle().stroke(color.opacity(a.opacity), lineWidth: 1.5)
                .frame(width: glyphSize, height: glyphSize)
                .position(x: x, y: y)
        } else {
            // Leaves / snow / pollen fall, swaying and turning.
            let y = -30 + CGFloat(prog) * (s.height + 60)
            let sway: CGFloat = a.kind == .snow ? 10 : 26
            let x = baseX + CGFloat(sin(t * (0.5 + r.v(6) * 0.6) + r.v(7) * 6)) * sway
            let rot = sin(t * (0.5 + r.v(8)) + r.v(7) * 6) * (a.kind == .snow ? 40 : 80)
            Image(systemName: a.kind.symbol)
                .font(.system(size: glyphSize))
                .foregroundStyle(color.opacity(a.opacity))
                .rotationEffect(.degrees(rot))
                .position(x: x, y: y)
        }
    }

    // ÉTÉ — fish swimming across the screen in vertical lanes, gently bobbing.
    @ViewBuilder
    private func fish(_ mem: Memory, _ r: Seed, _ i: Int, _ n: Int, _ t: Double, _ s: CGSize, _ c: Color) -> some View {
        let lane = (Double(i) + 0.5) / Double(max(1, n))
        let baseY = 40 + CGFloat(lane) * max(1, s.height - 80)
        let period = periodFor(r, salt: 3)
        let raw = (t / period) + r.v(4)
        let prog = raw - floor(raw)
        // Direction is re-rolled each crossing → fish randomly head left or right
        // over time (not a fixed per-fish side). They flip while off-screen.
        let dir: CGFloat = r.dir(Int(floor(raw)))
        let span = s.width + 200
        let x = dir > 0 ? -100 + CGFloat(prog) * span : s.width + 100 - CGFloat(prog) * span
        let y = baseY + CGFloat(sin(t * (0.55 + r.v(5) * 0.5) + r.v(6) * 6) * 20) // ample, unhurried bob
        node(mem, x: x, y: y, opacity: edgeFade(prog)) {
            Image(systemName: "fish.fill")
                .font(.system(size: 33 + r.v(7) * 15)) // ~1.5× bigger
                .foregroundStyle(c)
                .scaleEffect(x: dir, y: 1)
                .shadow(color: c.opacity(0.4), radius: 6)
        }
    }

    // AUTOMNE / HIVER — leaves flutter or snow drifts from top to bottom, swaying
    // and rotating as they fall.
    @ViewBuilder
    private func faller(_ mem: Memory, _ r: Seed, _ i: Int, _ n: Int, _ t: Double, _ s: CGSize, _ c: Color, snow: Bool) -> some View {
        let period = periodFor(r, salt: 2)
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
        let period = periodFor(r, salt: 2)
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
        HStack(spacing: 14) {
            yearCard
            card("SOUVENIRS") {
                Text("\(filteredMemories.count)").font(Typo.serif(26)).foregroundStyle(Palette.ink)
            }
        }
    }

    // Year picker: the years that actually hold souvenirs, plus "Toutes".
    private var yearCard: some View {
        Menu {
            Button("Toutes") { selectedYear = nil }
            ForEach(availableYears, id: \.self) { y in
                Button(String(y)) { selectedYear = y }
            }
        } label: {
            card("ANNÉE") {
                HStack(spacing: 6) {
                    Text(selectedYear.map(String.init) ?? "Toutes")
                        .font(Typo.serif(26)).foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func card(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Typo.mono(11)).tracking(1.5).foregroundStyle(Palette.muted)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x50323C).opacity(0.08), radius: 6, y: 3)
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
    // A direction (+1/-1) that varies per crossing index.
    func dir(_ crossing: Int) -> CGFloat {
        var h = Hasher(); h.combine(id); h.combine(crossing); h.combine(777)
        return (h.finalize() & 1) == 0 ? 1 : -1
    }
}

// Same idea as Seed but keyed by a particle index — ambient decor isn't a memory.
private struct AmbientSeed {
    let i: Int
    init(_ i: Int) { self.i = i }
    func v(_ salt: Int) -> Double {
        var h = Hasher(); h.combine(i); h.combine(salt); h.combine(31)
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

    // Decorative ambient particles drifting *behind* the souvenirs (never tappable,
    // never titled) — pure atmosphere. A memory stays the only real element.
    enum AmbientKind {
        case bubble, leaf, snow, petal
        var symbol: String {
            switch self {
            case .bubble: return "circle"
            case .leaf: return "leaf.fill"
            case .snow: return "snowflake"
            case .petal: return "circle.fill" // soft pollen dot
            }
        }
        var rises: Bool { self == .bubble } // bubbles go up, the rest fall
    }

    struct Ambient {
        let kind: AmbientKind
        let count: Int                      // how dense the season feels
        let period: ClosedRange<Double>     // seconds to cross the screen
        let size: ClosedRange<Double>
        let opacity: Double
    }

    /// All per-season pacing in one place — the dial to tune feel.
    /// `creaturePeriod` = seconds for one souvenir to cross / fall / bloom.
    struct Motion {
        let creaturePeriod: ClosedRange<Double>
        let ambient: Ambient
    }

    var motion: Motion {
        switch self {
        // L'océan : amples et lents, peu de remous ; quelques bulles qui montent.
        case .summer: return Motion(creaturePeriod: 12...20,
            ambient: Ambient(kind: .bubble, count: 16, period: 6...12, size: 4...11, opacity: 0.20))
        // La forêt : chutes plus vives, beaucoup de feuilles lointaines qui virevoltent.
        case .autumn: return Motion(creaturePeriod: 6...11,
            ambient: Ambient(kind: .leaf, count: 22, period: 5...9, size: 8...15, opacity: 0.16))
        // La neige : dense, lente, feutrée — beaucoup de flocons qui dérivent à peine.
        case .winter: return Motion(creaturePeriod: 14...24,
            ambient: Ambient(kind: .snow, count: 46, period: 12...22, size: 3...7, opacity: 0.22))
        // Le jardin : éclosions douces ; un peu de pollen qui flotte.
        case .spring: return Motion(creaturePeriod: 11...18,
            ambient: Ambient(kind: .petal, count: 16, period: 9...16, size: 4...9, opacity: 0.15))
        }
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id)
}
