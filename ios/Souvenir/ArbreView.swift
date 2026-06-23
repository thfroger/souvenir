import SwiftUI

/// Écran B — "Le ciel" (ex-Arbre). Instead of a static tree, the child's
/// memories drift in slowly, linger, then fade to make room for others — a calm,
/// ever-changing field where souvenirs surface at random. Colors follow the
/// season. Tap a dot to relive it immersively.
///
/// Pure client-side rendering of decrypted memories (DESIGN_INTEGRATION §3); no
/// content ever leaves the device.
struct ArbreView: View {
    let childID: UUID
    @EnvironmentObject private var store: MemoryStore
    @State private var openedMemory: Memory?
    @State private var start = Date()

    private var child: Child { SampleData.children.first { $0.id == childID } ?? SampleData.lea }

    private var memories: [Memory] {
        let all = store.memories(for: child)
        return Array((all.isEmpty ? SampleData.memories(for: child) : all).prefix(18))
    }

    private var season: Season { Season.current() }

    var body: some View {
        ZStack {
            LinearGradient(colors: [season.tint.opacity(0.22), Palette.paper],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                memoryField // confined below the header → never overlaps the name
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
            Text("LE CIEL DE")
                .font(Typo.mono(11)).tracking(3).foregroundStyle(Palette.muted)
            Text(child.name)
                .font(Typo.serif(32)).foregroundStyle(Palette.ink)
            Text(season.label)
                .font(Typo.mono(10)).tracking(2).foregroundStyle(Palette.faint)
        }
    }

    private var memoryField: some View {
        // Decrypt once per render — NOT inside the per-frame TimelineView closure
        // (that would re-decrypt + re-id every memory 60×/s, teleporting the dots).
        let mems = memories
        return GeometryReader { geo in
            TimelineView(.animation) { timeline in
                // Elapsed since the screen opened — small values, exact precision,
                // unambiguously 1× real time.
                let t = timeline.date.timeIntervalSince(start)
                ZStack {
                    ForEach(Array(mems.enumerated()), id: \.element.id) { i, mem in
                        dot(mem, index: i, count: mems.count, t: t, size: geo.size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder private func dot(_ mem: Memory, index: Int, count: Int, t: Double, size: CGSize) -> some View {
        let r = Seed(mem.id)
        let duration = 52 + r.v(1) * 40 // 52..92 s per appear→drift→fade cycle (slow & calm)
        // Phases spread evenly by index (+ small jitter) so the field is never
        // empty — a few souvenirs are always present while others come and go.
        let phase = Double(index) / Double(max(1, count)) + r.v(2) * 0.12
        let local = ((t / duration) + phase).truncatingRemainder(dividingBy: 1)
        let op = pulse(local)
        if op > 0.01 {
            let pad: CGFloat = 48
            let baseX = pad + CGFloat(r.v(3)) * max(1, size.width - 2 * pad)
            let baseY = pad + CGFloat(r.v(4)) * max(1, size.height - 2 * pad)
            let angle = r.v(5) * 2 * .pi
            let dist = CGFloat(28 + r.v(6) * 34) * CGFloat(local)
            let diameter = CGFloat(12 + r.v(7) * 12)
            let color = season.palette[r.idx(8, season.palette.count)]
            Button { openedMemory = mem } label: {
                VStack(spacing: 7) {
                    Circle()
                        .fill(color)
                        .frame(width: diameter, height: diameter)
                        .shadow(color: color.opacity(0.7), radius: 10)
                    Text(mem.title)
                        .font(Typo.serif(13))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            .opacity(op)
            .position(x: baseX + cos(angle) * dist, y: baseY + sin(angle) * dist)
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

// A dot's opacity over its cycle: fades in, lingers, fades out, then is absent
// for the rest (leaving room for others). local ∈ [0,1).
private func pulse(_ local: Double) -> Double {
    guard local < 0.52 else { return 0 }
    return min(smoothstep(0, 0.10, local), 1 - smoothstep(0.40, 0.52, local))
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

// Deterministic per-memory pseudo-random values (stable within a session), so a
// dot keeps its base position / phase / colour across frames and only the
// intended drift moves it.
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
        case .spring: return [Palette.vert, Palette.rose, Palette.lilas, Palette.jaune]
        case .summer: return [Palette.peche, Palette.jaune, Palette.accent, Palette.bleu]
        case .autumn: return [Palette.accent, Palette.peche, Palette.jaune, Color(hex: 0xC9762F)]
        case .winter: return [Palette.bleu, Palette.lilas, Palette.rose, Color(hex: 0x9FB4C7)]
        }
    }

    var tint: Color {
        switch self {
        case .spring: return Palette.vert
        case .summer: return Palette.peche
        case .autumn: return Palette.accent
        case .winter: return Palette.bleu
        }
    }
}

#Preview {
    ArbreView(childID: SampleData.lea.id)
}
