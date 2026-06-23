import SwiftUI

/// Immersive memory view (écran C, the design's priority screen — DESIGN.md §3.B).
/// Rises from the bottom over the current screen; large visual + editorial sheet,
/// voice player, milestone chip. No heart/like (removed from scope, erratum §6).
struct ImmersiveMemoryView: View {
    let memory: Memory
    let child: Child
    let onClose: () -> Void

    private var metaLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM yyyy"
        let dateStr = f.string(from: memory.date).uppercased()
        let age = max(0, Calendar.current.component(.year, from: memory.date) - child.birthYear)
        return "\(dateStr) · \(age) ANS"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(spacing: -28) {
                    headerVisual
                        .frame(height: 430)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    sheet
                }
            }
            .ignoresSafeArea(edges: .top)

            backButton
                .padding(.leading, 20)
                .padding(.top, 8)
        }
    }

    // MARK: header visual

    @ViewBuilder private var headerVisual: some View {
        switch memory.kind {
        case .citation:
            ZStack {
                LinearGradient(colors: memory.pastel, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("\u{201C}")
                    .font(.system(size: 120, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .photo, .drawing:
            PhotoPlaceholder(colors: memory.pastel)
        default:
            ZStack {
                LinearGradient(colors: memory.pastel, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: memory.kind.icon ?? "sparkles")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var backButton: some View {
        Button(action: onClose) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }

    // MARK: editorial sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(metaLine)
                .font(.system(.caption2, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color(hex: 0xB3A591))

            Text(memory.title)
                .font(.system(size: 36, design: .serif))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if memory.kind == .citation, let quote = memory.note {
                Text(quote)
                    .font(.system(size: 26, design: .serif))
                    .foregroundStyle(Palette.inkSoft)
            } else if let note = memory.note {
                Text(note)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if memory.kind == .voice {
                VoicePlayerView(duration: memory.audio ?? "0:00", caption: "la voix de \(child.name)")
            }

            if memory.kind == .milestone {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").foregroundStyle(Palette.vert)
                    Text("Jalon").font(.system(.subheadline, design: .serif)).foregroundStyle(Palette.ink)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Palette.chip, in: Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
    }
}

// MARK: - Voice player (DESIGN.md §3.B)

/// Play/pause + a waveform that fills with terracotta as it progresses.
/// PLACEHOLDER playback: progress is simulated (there is no decrypted audio blob
/// yet). To be replaced by an AVAudioPlayer over the decrypted audio
/// (DESIGN_INTEGRATION.md §5) — never any cloud speech API.
struct VoicePlayerView: View {
    let duration: String
    let caption: String

    @State private var progress: Double = 0
    @State private var playing = false

    private let bars: [CGFloat] = [10, 18, 26, 14, 30, 22, 34, 20, 28, 16, 24, 12, 22, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Palette.accent, in: Circle())
                }
                waveform
                Text(duration)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0xA89C8E))
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            guard playing else { return }
            progress = min(1, progress + 0.012)
            if progress >= 1 { playing = false }
        }
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(Double(i) / Double(bars.count) <= progress ? Palette.accent : Palette.chip)
                    .frame(width: 3, height: bars[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ImmersiveMemoryView(
        memory: Memory(childID: SampleData.lea.id, kind: .voice, daysAgo: 1,
                       title: "La voix de Léa", note: "Ses premiers babillages, un dimanche matin.",
                       audio: "0:42", pastel: [Palette.peche, Palette.jaune]),
        child: SampleData.lea,
        onClose: {}
    )
}
