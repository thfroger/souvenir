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
    @State private var field = FallingField() // physics for falling seasons
    #if DEBUG
    // Dev-only: lets Réglages force a season to tune the scene. Compiled out of
    // release builds, so the app always follows the real date when shipped.
    @AppStorage("debugSeason") private var debugSeason = "auto"
    #endif

    private var child: Child { SampleData.children.first { $0.id == childID } ?? SampleData.lea }
    private var season: Season {
        #if DEBUG
        if let forced = Season(debugName: debugSeason) { return forced }
        #endif
        return Season.current()
    }

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
                    if season.motion.fall != nil {
                        // Autumn leaves / winter snow: a real physics field so falling
                        // souvenirs bounce off each other and never overlap.
                        fallingScene(mems, t: t, size: geo.size)
                    } else {
                        ForEach(Array(mems.enumerated()), id: \.element.id) { i, mem in
                            element(mem, index: i, count: mems.count, t: t, size: geo.size)
                        }
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
        case .spring: flower(mem, r, index, count, t, size, color)
        case .autumn, .winter: EmptyView() // handled by fallingScene (physics)
        }
    }

    // AUTOMNE / HIVER — souvenirs fall under a small physics field: gentle gravity,
    // wall bounces, and elastic collisions so two never sit on top of each other.
    @ViewBuilder
    private func fallingScene(_ mems: [Memory], t: Double, size: CGSize) -> some View {
        let snow = season == .winter
        let fall = season.motion.fall ?? .init(speed: 60, sway: 20)
        // Step the simulation for this frame (TimelineView already redraws at 60fps;
        // the field is a plain reference, so this doesn't re-enter SwiftUI state).
        let _ = field.frame(mems.enumerated().map { idx, mem in
            let r = Seed(mem.id)
            let glyph = snow ? 27 + r.v(7) * 12 : 20 + r.v(7) * 10
            return FallingField.Spec(id: mem.id, glyph: CGFloat(glyph), index: idx, count: mems.count)
        }, fall: fall, at: t, size: size)

        ForEach(field.bodies, id: \.id) { body in
            if let mem = mems.first(where: { $0.id == body.id }) {
                let color = season.palette[Seed(mem.id).idx(9, season.palette.count)]
                node(mem, x: body.pos.x, y: body.pos.y, opacity: 1) {
                    Image(systemName: snow ? "snowflake" : "leaf.fill")
                        .font(.system(size: body.glyph))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(body.spin))
                        .shadow(color: color.opacity(0.3), radius: 4)
                }
            }
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

// Deterministic 64-bit mix (splitmix64). Unlike Swift's `Hasher` — which is
// re-seeded randomly every process launch — this is stable across launches, so
// the scene's per-element variation never accidentally collapses (all elements
// landing on near-equal values) depending on the run's hash seed.
private func mix64(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

private func uuidSeed(_ id: UUID) -> UInt64 {
    let b = id.uuid
    let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
           | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
    let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
           | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
    return mix64(hi ^ mix64(lo))
}

private func salted(_ base: UInt64, _ salt: Int) -> UInt64 {
    mix64(base ^ (UInt64(bitPattern: Int64(salt)) &* 0x9E37_79B9_7F4A_7C15))
}

// Deterministic, well-distributed per-memory pseudo-random values.
private struct Seed {
    let base: UInt64
    init(_ id: UUID) { base = uuidSeed(id) }
    func v(_ salt: Int) -> Double { Double(salted(base, salt) % 1_000_000) / 1_000_000.0 }
    func idx(_ salt: Int, _ mod: Int) -> Int { Int(salted(base, salt) % UInt64(max(1, mod))) }
    // A direction (+1/-1) that varies per crossing index.
    func dir(_ crossing: Int) -> CGFloat { (salted(base, 777 &+ crossing) & 1) == 0 ? 1 : -1 }
}

// Same idea as Seed but keyed by a particle index — ambient decor isn't a memory.
private struct AmbientSeed {
    let base: UInt64
    init(_ i: Int) { base = mix64(UInt64(bitPattern: Int64(i)) &+ 0x1234_5678) }
    func v(_ salt: Int) -> Double { Double(salted(base, salt) % 1_000_000) / 1_000_000.0 }
    func idx(_ salt: Int, _ mod: Int) -> Int { Int(salted(base, salt) % UInt64(max(1, mod))) }
}

// A tiny deterministic RNG seeded from a souvenir id, advancing on each `next()`.
private struct SeededRNG {
    private var state: UInt64
    init(_ id: UUID, _ salt: Int = 0) { state = salted(uuidSeed(id), salt) }
    mutating func next() -> CGFloat {
        state = mix64(state)
        return CGFloat(state % 1_000_000) / 1_000_000.0
    }
}

/// A small physics field for the seasons whose souvenirs fall (autumn leaves,
/// winter snow). Each souvenir is a soft disc that drifts down under gentle
/// gravity, bounces off the side walls, and collides elastically with the others
/// — so two flakes never sit on top of each other. Held as plain state and
/// stepped from the scene's TimelineView (no SwiftUI re-entrancy).
final class FallingField {
    struct Spec { let id: UUID; let glyph: CGFloat; let index: Int; let count: Int }
    struct Body: Identifiable {
        let id: UUID
        var pos: CGPoint
        var vel: CGVector
        var radius: CGFloat
        var glyph: CGFloat
        var spin: Double
        var vTarget: CGFloat  // this leaf's own terminal fall speed (varied → desync)
        var swayFreq: Double  // flutter frequency
        var swayPhase: Double // flutter phase
        var swayAccel: CGFloat // flutter strength
        var index: Int        // lane assignment, kept for respawn
        var count: Int
    }

    private(set) var bodies: [Body] = []
    private var lastT: Double = 0
    private var size: CGSize = .zero
    private var speed: CGFloat = 50
    private var swayBase: CGFloat = 12

    /// Per-frame entry point: reconcile the body set with the current souvenirs,
    /// adopt the season's fall tuning, then advance one step.
    func frame(_ specs: [Spec], fall: Season.Fall, at t: Double, size: CGSize) {
        self.size = size
        speed = fall.speed
        swayBase = fall.sway
        sync(specs)
        step(to: t)
    }

    private func sync(_ specs: [Spec]) {
        let wanted = Dictionary(specs.map { ($0.id, $0.glyph) }, uniquingKeysWith: { a, _ in a })
        bodies.removeAll { wanted[$0.id] == nil }
        let present = Set(bodies.map { $0.id })
        for spec in specs where !present.contains(spec.id) {
            bodies.append(spawn(spec, fresh: false))
        }
        // Keep radii in sync if the glyph size changed (e.g. switching autumn↔winter).
        for i in bodies.indices {
            if let glyph = wanted[bodies[i].id] {
                bodies[i].glyph = glyph
                bodies[i].radius = glyph * 0.5 // wide enough that the leaves don't visually overlap
            }
        }
    }

    private func spawn(_ spec: Spec, fresh: Bool) -> Body {
        var rng = SeededRNG(spec.id, fresh ? Int(lastT * 1000) : 0)
        let radius = spec.glyph * 0.5
        // Horizontal lane by index (+ jitter) so even a handful of leaves spread
        // across the width instead of clustering on a random per-id position.
        let lane = (CGFloat(spec.index) + 0.5) / CGFloat(max(1, spec.count))
        let jitter = (rng.next() - 0.5) * (size.width / CGFloat(max(1, spec.count))) * 0.7
        let x = min(max(radius, lane * size.width + jitter), size.width - radius)
        // Respawn enters just above the top; the initial fill spreads down the whole
        // height so the scene is populated from the first frame (not slowly drifting in).
        let y = fresh ? -radius : rng.next() * max(1, size.height)
        let vTarget = speed * (0.6 + rng.next() * 0.9)        // 0.6–1.5× → each falls at its own pace
        let swayFreq = 0.6 + Double(rng.next()) * 1.7         // rad/s, per leaf → no shared rhythm
        let swayPhase = Double(rng.next()) * 6.2832
        let swayAccel = swayBase * (0.7 + rng.next() * 0.9)
        return Body(id: spec.id, pos: CGPoint(x: x, y: y),
                    vel: CGVector(dx: (rng.next() - 0.5) * swayBase, dy: vTarget),
                    radius: radius, glyph: spec.glyph, spin: Double(rng.next()) * 360,
                    vTarget: vTarget, swayFreq: swayFreq, swayPhase: swayPhase, swayAccel: swayAccel,
                    index: spec.index, count: spec.count)
    }

    private func step(to t: Double) {
        defer { lastT = t }
        guard lastT != 0 else { return }
        let dt = min(t - lastT, 1.0 / 30) // clamp hitches so collisions stay stable
        guard dt > 0 else { return }
        for i in bodies.indices {
            // Side-to-side flutter — per-leaf frequency/phase so no two move alike.
            let osc = CGFloat(sin(t * bodies[i].swayFreq + bodies[i].swayPhase))
            bodies[i].vel.dx += osc * bodies[i].swayAccel * CGFloat(dt)
            bodies[i].vel.dx *= 0.95 // damp so flutter stays bounded
            // Ease toward this leaf's own terminal speed instead of a shared gravity
            // (which would make every leaf fall at the same rate and bunch up).
            bodies[i].vel.dy += (bodies[i].vTarget - bodies[i].vel.dy) * 2.0 * CGFloat(dt)
            bodies[i].pos.x += bodies[i].vel.dx * CGFloat(dt)
            bodies[i].pos.y += bodies[i].vel.dy * CGFloat(dt)
            bodies[i].spin += Double(bodies[i].vel.dx) * dt * 1.2
            let r = bodies[i].radius
            if bodies[i].pos.x < r { bodies[i].pos.x = r; bodies[i].vel.dx = abs(bodies[i].vel.dx) }
            if bodies[i].pos.x > size.width - r {
                bodies[i].pos.x = size.width - r; bodies[i].vel.dx = -abs(bodies[i].vel.dx)
            }
            if bodies[i].pos.y - r > size.height {
                bodies[i] = spawn(Spec(id: bodies[i].id, glyph: bodies[i].glyph,
                                       index: bodies[i].index, count: bodies[i].count), fresh: true)
            }
        }
        resolveCollisions()
    }

    // Equal-mass elastic resolution: separate the overlap, then reflect the
    // relative velocity along the contact normal so they head off in new directions.
    private func resolveCollisions() {
        guard bodies.count > 1 else { return }
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let dx = bodies[j].pos.x - bodies[i].pos.x
                let dy = bodies[j].pos.y - bodies[i].pos.y
                let minDist = bodies[i].radius + bodies[j].radius
                let distSq = dx * dx + dy * dy
                guard distSq < minDist * minDist, distSq > 0.0001 else { continue }
                let dist = sqrt(distSq)
                let nx = dx / dist, ny = dy / dist
                let overlap = (minDist - dist) / 2
                bodies[i].pos.x -= nx * overlap; bodies[i].pos.y -= ny * overlap
                bodies[j].pos.x += nx * overlap; bodies[j].pos.y += ny * overlap
                let rvn = (bodies[j].vel.dx - bodies[i].vel.dx) * nx
                        + (bodies[j].vel.dy - bodies[i].vel.dy) * ny
                guard rvn < 0 else { continue } // only if approaching
                let imp = -(1 + 0.85) * rvn / 2 // restitution 0.85
                bodies[i].vel.dx -= imp * nx; bodies[i].vel.dy -= imp * ny
                bodies[j].vel.dx += imp * nx; bodies[j].vel.dy += imp * ny
            }
        }
    }
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

    // Dev-only mapping for the Réglages season selector ("auto" → nil → real date).
    init?(debugName: String) {
        switch debugName {
        case "spring": self = .spring
        case "summer": self = .summer
        case "autumn": self = .autumn
        case "winter": self = .winter
        default: return nil
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

    // Falling souvenirs (autumn/winter) run through the physics field instead of a
    // stateless period; nil for seasons that don't fall (swim/bloom).
    struct Fall {
        let speed: CGFloat // downward drift, points per second
        let sway: CGFloat  // horizontal spread of the initial drift
    }

    /// All per-season pacing in one place — the dial to tune feel.
    /// `creaturePeriod` drives swim/bloom seasons; `fall` drives the physics ones.
    struct Motion {
        let creaturePeriod: ClosedRange<Double>
        let ambient: Ambient
        var fall: Fall? = nil
    }

    var motion: Motion {
        switch self {
        // L'océan : amples et lents, peu de remous ; quelques bulles qui montent.
        case .summer: return Motion(creaturePeriod: 12...20,
            ambient: Ambient(kind: .bubble, count: 16, period: 6...12, size: 4...11, opacity: 0.20))
        // La forêt : feuilles qui tombent (×0,8, plus posées) et rebondissent entre elles.
        case .autumn: return Motion(creaturePeriod: 6...11,
            ambient: Ambient(kind: .leaf, count: 22, period: 5...9, size: 8...15, opacity: 0.16),
            fall: Fall(speed: 44, sway: 28))
        // La neige : dense, lente, feutrée ; les flocons-souvenirs rebondissent.
        case .winter: return Motion(creaturePeriod: 14...24,
            ambient: Ambient(kind: .snow, count: 46, period: 12...22, size: 3...7, opacity: 0.22),
            fall: Fall(speed: 34, sway: 16))
        // Le jardin : éclosions douces ; un peu de pollen qui flotte.
        case .spring: return Motion(creaturePeriod: 11...18,
            ambient: Ambient(kind: .petal, count: 16, period: 9...16, size: 4...9, opacity: 0.15))
        }
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id)
}
