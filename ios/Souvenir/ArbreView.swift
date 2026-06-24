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
    @Binding var openedMemory: Memory?
    @State private var start = Date()
    @State private var selectedYear: Int? // nil = Toutes
    @State private var sky = SkyField() // rotating cast of ~5 souvenirs
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
                    skyScene(mems, t: t, size: geo.size)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // The living stage: a small rotating cast (~5) of souvenirs drawn at random
    // from the collection, each with random position/heading/colour/size, drifting
    // with the season's flavour and never overlapping. Stepped from the TimelineView
    // (the field is a plain reference → no SwiftUI re-entrancy).
    private func skyScene(_ mems: [Memory], t: Double, size: CGSize) -> some View {
        let sk = season.sky
        let _ = sky.frame(pool: mems, style: sk, palette: season.palette, at: t, size: size)
        return ForEach(sky.bodies) { body in
            node(body.memory, x: body.pos.x, y: body.pos.y, opacity: sky.opacity(of: body, style: sk.style)) {
                skyGlyph(body, style: sk)
            }
        }
    }

    @ViewBuilder
    private func skyGlyph(_ body: SkyField.Body, style: Season.Sky) -> some View {
        switch style.style {
        case .bloom:
            FlowerGlyph(petal: body.color)
                .scaleEffect(min(1, smoothstep(0, 1.5, body.age)), anchor: .bottom)
        case .swim:
            Image(systemName: style.symbol)
                .font(.system(size: body.glyph))
                .foregroundStyle(body.color)
                .scaleEffect(x: body.facing, y: 1) // face the way it swims
                .shadow(color: body.color.opacity(0.4), radius: 6)
        case .fall:
            Image(systemName: style.symbol)
                .font(.system(size: body.glyph))
                .foregroundStyle(body.color)
                .rotationEffect(.degrees(body.spin))
                .shadow(color: body.color.opacity(0.3), radius: 4)
        }
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

    // A tappable souvenir: its seasonal glyph + a faint title that fades with it.
    private func node(_ mem: Memory, x: CGFloat, y: CGFloat, opacity: Double,
                      @ViewBuilder glyph: () -> some View) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.7)) { openedMemory = mem } } label: {
            VStack(spacing: 4) {
                glyph()
                Text(mem.title)
                    .font(Typo.serif(11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 96)
                    .fixedSize(horizontal: false, vertical: true)
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

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

// Deterministic 64-bit mix (splitmix64), stable across launches — used for the
// ambient decor so it never accidentally clusters depending on the run's seed.
private func mix64(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

private func salted(_ base: UInt64, _ salt: Int) -> UInt64 {
    mix64(base ^ (UInt64(bitPattern: Int64(salt)) &* 0x9E37_79B9_7F4A_7C15))
}

// Deterministic, well-distributed pseudo-random values keyed by a particle index
// — the ambient decor isn't a souvenir, so it stays stable rather than random.
private struct AmbientSeed {
    let base: UInt64
    init(_ i: Int) { base = mix64(UInt64(bitPattern: Int64(i)) &+ 0x1234_5678) }
    func v(_ salt: Int) -> Double { Double(salted(base, salt) % 1_000_000) / 1_000_000.0 }
    func idx(_ salt: Int, _ mod: Int) -> Int { Int(salted(base, salt) % UInt64(max(1, mod))) }
}

/// The Ciel's living stage: a small rotating cast (≈5) of souvenirs drawn at
/// random from the whole collection. Each drifts with the season's flavour
/// (fish swim & turn, leaves/snow fall, flowers bloom in place), never overlaps
/// another, then fades out and is replaced by a *different* random souvenir —
/// random position, heading, colour and size each time. Plain state, stepped
/// from the scene's TimelineView (no SwiftUI re-entrancy). Uses true randomness:
/// the cast is ephemeral, so nothing needs to be stable across launches.
final class SkyField {
    struct Body: Identifiable {
        let id: Int          // stable on-screen slot → SwiftUI views stay put as the cast rotates
        var memory: Memory
        var pos: CGPoint
        var vel: CGVector
        var radius: CGFloat
        var glyph: CGFloat
        var hw: CGFloat      // half-width of the whole node (glyph + title) for no-overlap
        var hh: CGFloat      // half-height of the whole node
        var color: Color
        var spin: Double
        var age: Double
        var lifetime: Double
        var wanderPhase: Double
        var wanderRate: Double
        var facing: CGFloat
    }

    private(set) var bodies: [Body] = []
    private var lastT: Double = 0
    private var size: CGSize = .zero
    private var rng = SystemRandomNumberGenerator()
    private static let maxOnScreen = 5
    // Keep the glyph *and its centred title* (≤96pt) from leaving the screen.
    private static let labelMargin: CGFloat = 50

    func frame(pool: [Memory], style: Season.Sky, palette: [Color], at t: Double, size: CGSize) {
        self.size = size
        let target = min(Self.maxOnScreen, pool.count)
        if lastT == 0 { lastT = t }
        var dt = t - lastT; lastT = t
        dt = min(max(dt, 0), 1.0 / 30)

        // Drop bodies whose souvenir left the pool (year filter / child change), and
        // resize the cast to the target count.
        bodies.removeAll { b in !pool.contains { $0.id == b.memory.id } }
        if bodies.count > target { bodies.removeLast(bodies.count - target) }
        while bodies.count < target {
            // Initial fill spreads across the visible height (entering: false) so the
            // scene is populated at once rather than slowly drifting in from the top.
            bodies.append(spawn(slot: bodies.count, pool: pool, style: style, palette: palette, entering: false))
        }
        guard dt > 0 else { return }

        for i in bodies.indices {
            bodies[i].age += dt
            switch style.style {
            case .bloom:
                break // rooted; only blooms (scale) and fades
            case .swim:
                let turn = sin(t * bodies[i].wanderRate + bodies[i].wanderPhase) * 0.9
                rotate(&bodies[i].vel, by: turn * dt)
                bodies[i].pos.x += bodies[i].vel.dx * CGFloat(dt)
                bodies[i].pos.y += bodies[i].vel.dy * CGFloat(dt)
                bounceAllWalls(&bodies[i])
                bodies[i].facing = bodies[i].vel.dx >= 0 ? 1 : -1
            case .fall:
                let osc = CGFloat(sin(t * bodies[i].wanderRate * 2 + bodies[i].wanderPhase))
                bodies[i].vel.dx += osc * 12 * CGFloat(dt)
                bodies[i].vel.dx *= 0.96
                bodies[i].pos.x += bodies[i].vel.dx * CGFloat(dt)
                bodies[i].pos.y += bodies[i].vel.dy * CGFloat(dt)
                bodies[i].spin += Double(bodies[i].vel.dx) * dt * 1.2
                bounceSideWalls(&bodies[i])
            }
        }
        resolveCollisions()

        // Recycle: a faded-out (or fallen-off-the-bottom) souvenir is replaced by a
        // fresh random one, so the cast keeps rotating.
        for i in bodies.indices {
            let fellOff = style.style == .fall && bodies[i].pos.y - bodies[i].radius > size.height
            if fellOff {
                bodies[i] = spawn(slot: bodies[i].id, pool: pool, style: style, palette: palette, entering: true)
            } else if style.style != .fall && bodies[i].age > bodies[i].lifetime {
                bodies[i] = spawn(slot: bodies[i].id, pool: pool, style: style, palette: palette, entering: false)
            }
        }
    }

    // Fade in on arrival; swim/bloom also fade out near end of life (falling ones
    // simply exit the bottom).
    func opacity(of b: Body, style: Season.SkyStyle) -> Double {
        let fadeIn = smoothstep(0, 1.2, b.age)
        guard style != .fall else { return fadeIn }
        return min(fadeIn, smoothstep(0, 1.6, b.lifetime - b.age))
    }

    private func spawn(slot: Int, pool: [Memory], style: Season.Sky, palette: [Color], entering: Bool) -> Body {
        // Prefer a souvenir not already on screen, so the cast shows variety.
        let shown = Set(bodies.filter { $0.id != slot }.map { $0.memory.id })
        let choices = pool.filter { !shown.contains($0.id) }
        let mem = (choices.isEmpty ? pool : choices).randomElement(using: &rng) ?? pool[0]
        let glyph = CGFloat.random(in: style.glyph, using: &rng)
        let radius = glyph * 0.5
        let color = palette.randomElement(using: &rng) ?? .gray
        let speed = CGFloat.random(in: style.speed, using: &rng)
        // Whole-node half-extents (glyph + title beneath it) so separation prevents
        // glyph–glyph *and* glyph–title overlap. Title width ~6pt/char, capped at 96.
        let titleW = min(96, CGFloat(mem.title.count) * 6 + 8)
        let hw = max(radius, titleW * 0.5) + 4
        let hh = (glyph + 22) * 0.5 + 2 // glyph + spacing + one title line
        let pos: CGPoint
        let vel: CGVector
        switch style.style {
        case .fall:
            let m = max(radius, Self.labelMargin)
            let x = CGFloat.random(in: m...max(m, size.width - m), using: &rng)
            // Recycled flakes enter just above the top; the initial fill is spread
            // down the visible height so the scene starts populated.
            let y = entering
                ? -radius - CGFloat.random(in: 0...max(1, size.height * 0.3), using: &rng)
                : CGFloat.random(in: -radius...max(1, size.height * 0.85), using: &rng)
            pos = CGPoint(x: x, y: y)
            vel = CGVector(dx: CGFloat.random(in: -10...10, using: &rng), dy: max(8, speed))
        case .swim:
            pos = freePosition(hw: hw, hh: hh)
            let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
            let ang = Double.random(in: -0.5...0.5, using: &rng) // mostly horizontal, some rise/dive
            vel = CGVector(dx: dir * speed * CGFloat(cos(ang)), dy: speed * CGFloat(sin(ang)) * 0.6)
        case .bloom:
            pos = freePosition(hw: hw, hh: hh)
            vel = .zero
        }
        return Body(id: slot, memory: mem, pos: pos, vel: vel, radius: radius, glyph: glyph,
                    hw: hw, hh: hh, color: color, spin: Double.random(in: 0...360, using: &rng), age: 0,
                    lifetime: Double.random(in: 10...20, using: &rng),
                    wanderPhase: Double.random(in: 0...6.2832, using: &rng),
                    wanderRate: Double.random(in: 0.3...0.8, using: &rng),
                    facing: vel.dx >= 0 ? 1 : -1)
    }

    // A random on-screen spot whose node box doesn't land on another souvenir's.
    private func freePosition(hw: CGFloat, hh: CGFloat) -> CGPoint {
        let xr = hw...max(hw, size.width - hw)
        let yr = hh...max(hh, size.height - hh)
        for _ in 0..<18 {
            let p = CGPoint(x: .random(in: xr, using: &rng), y: .random(in: yr, using: &rng))
            let clear = bodies.allSatisfy { b in
                abs(b.pos.x - p.x) > b.hw + hw + 4 || abs(b.pos.y - p.y) > b.hh + hh + 4
            }
            if clear { return p }
        }
        return CGPoint(x: .random(in: xr, using: &rng), y: .random(in: yr, using: &rng))
    }

    private func rotate(_ v: inout CGVector, by a: Double) {
        let c = CGFloat(cos(a)), s = CGFloat(sin(a))
        v = CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }

    private func bounceAllWalls(_ b: inout Body) {
        let mx = max(b.radius, Self.labelMargin)
        let my = max(b.radius, 30)
        if b.pos.x < mx { b.pos.x = mx; b.vel.dx = abs(b.vel.dx) }
        if b.pos.x > size.width - mx { b.pos.x = size.width - mx; b.vel.dx = -abs(b.vel.dx) }
        if b.pos.y < my { b.pos.y = my; b.vel.dy = abs(b.vel.dy) }
        if b.pos.y > size.height - my { b.pos.y = size.height - my; b.vel.dy = -abs(b.vel.dy) }
    }

    private func bounceSideWalls(_ b: inout Body) {
        let mx = max(b.radius, Self.labelMargin)
        if b.pos.x < mx { b.pos.x = mx; b.vel.dx = abs(b.vel.dx) }
        if b.pos.x > size.width - mx { b.pos.x = size.width - mx; b.vel.dx = -abs(b.vel.dx) }
    }

    // Box (AABB) separation over each node's full extent (glyph + title), so two
    // souvenirs never overlap — neither glyph–glyph nor glyph–title. Resolve along
    // the axis of least penetration, then nudge them apart.
    private func resolveCollisions() {
        guard bodies.count > 1 else { return }
        // A couple of passes so chains of three settle without residual overlap.
        for _ in 0..<2 {
            for i in 0..<bodies.count {
                for j in (i + 1)..<bodies.count {
                    let dx = bodies[j].pos.x - bodies[i].pos.x
                    let dy = bodies[j].pos.y - bodies[i].pos.y
                    let ox = (bodies[i].hw + bodies[j].hw) - abs(dx) // x penetration
                    let oy = (bodies[i].hh + bodies[j].hh) - abs(dy) // y penetration
                    guard ox > 0, oy > 0 else { continue }
                    if ox <= oy {
                        let nx: CGFloat = dx < 0 ? -1 : 1
                        bodies[i].pos.x -= nx * ox / 2; bodies[j].pos.x += nx * ox / 2
                        bodies[i].vel.dx -= nx * 6; bodies[j].vel.dx += nx * 6
                    } else {
                        let ny: CGFloat = dy < 0 ? -1 : 1
                        bodies[i].pos.y -= ny * oy / 2; bodies[j].pos.y += ny * oy / 2
                        bodies[i].vel.dy -= ny * 6; bodies[j].vel.dy += ny * 6
                    }
                }
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

    struct Motion { let ambient: Ambient }

    // Calm ambient decor behind the small souvenir cast (counts kept low so the
    // scene stays uncluttered — the souvenirs are the actors).
    var motion: Motion {
        switch self {
        case .summer: return Motion(ambient: Ambient(kind: .bubble, count: 8, period: 6...12, size: 4...11, opacity: 0.18))
        case .autumn: return Motion(ambient: Ambient(kind: .leaf, count: 10, period: 5...9, size: 8...15, opacity: 0.14))
        case .winter: return Motion(ambient: Ambient(kind: .snow, count: 22, period: 12...22, size: 3...7, opacity: 0.20))
        case .spring: return Motion(ambient: Ambient(kind: .petal, count: 8, period: 9...16, size: 4...9, opacity: 0.14))
        }
    }

    // How the souvenir cast moves this season (the SkyField stage). Tunable dials.
    enum SkyStyle { case swim, fall, bloom }
    struct Sky {
        let style: SkyStyle
        let speed: ClosedRange<CGFloat> // points per second
        let glyph: ClosedRange<CGFloat> // font size
        let symbol: String              // SF Symbol (ignored for .bloom → FlowerGlyph)
    }

    var sky: Sky {
        switch self {
        case .summer: return Sky(style: .swim, speed: 20...44, glyph: 30...48, symbol: "fish.fill")
        case .autumn: return Sky(style: .fall, speed: 26...46, glyph: 22...32, symbol: "leaf.fill")
        case .winter: return Sky(style: .fall, speed: 18...34, glyph: 40...58, symbol: "snowflake") // ×1,5, tailles variées
        case .spring: return Sky(style: .bloom, speed: 0...0, glyph: 26...36, symbol: "")
        }
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id, openedMemory: .constant(nil))
}
