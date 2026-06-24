import SwiftUI
import UIKit
import AVFoundation

/// Immersive memory view (écran C, the design's priority screen — DESIGN.md §3.B).
/// Rises from the bottom over the current screen; large visual + editorial sheet,
/// voice player, milestone chip. No heart/like (removed from scope, erratum §6).
struct ImmersiveMemoryView: View {
    let memory: Memory
    let child: Child
    let onClose: () -> Void

    // Pinch-to-zoom state for photo/drawing memories.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

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

            if memory.imageData != nil {
                photoLayout // full-bleed, pinch-to-zoom, caption fades on zoom
            } else {
                scrollLayout
            }

            backButton
                .padding(.leading, 16)
                .padding(.top, 10)
        }
    }

    private var scrollLayout: some View {
        ScrollView {
            VStack(spacing: -28) {
                headerVisual
                sheet
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: photo layout (zoomable)

    /// How visible the caption is — it fades almost entirely as soon as you start
    /// zooming, so the photo gets the full screen.
    private var captionOpacity: Double {
        scale <= 1.01 ? 1 : max(0, Double(1 - (scale - 1) * 2.5))
    }

    @ViewBuilder private var photoLayout: some View {
        if let data = memory.imageData, let ui = UIImage(data: data) {
            ZStack(alignment: .bottom) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(zoomGesture.simultaneously(with: panGesture))
                    .onTapGesture(count: 2) { toggleZoom() }

                photoCaption
                    .opacity(captionOpacity)
                    .allowsHitTesting(captionOpacity > 0.5)
                    .animation(.easeOut(duration: 0.2), value: captionOpacity)
            }
            .ignoresSafeArea()
        }
    }

    // Compact caption that floats over the bottom of the photo (no tall sheet).
    private var photoCaption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metaLine)
                .font(Typo.mono(10)).tracking(1.5)
                .foregroundStyle(Color(hex: 0xB3A591))
            Text(memory.title)
                .font(Typo.serif(28))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if memory.kind != .citation, let note = memory.note {
                Text(note)
                    .font(Typo.sans(14)).lineSpacing(4)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(.easeOut(duration: 0.25)) { offset = .zero; lastOffset = .zero }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if scale > 1 {
                scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
            } else {
                scale = 2.2; lastScale = 2.2
            }
        }
    }

    // MARK: header visual

    @ViewBuilder private var headerVisual: some View {
        if let data = memory.imageData, let ui = UIImage(data: data) {
            // Show the photo at its natural aspect (no crop), capped — a landscape
            // photo stays short instead of being forced into a tall frame.
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 540)
        } else {
            coloredHeader
                .frame(height: 430)
                .frame(maxWidth: .infinity)
                .clipped()
        }
    }

    @ViewBuilder private var coloredHeader: some View {
        switch memory.kind {
        case .citation:
            ZStack {
                LinearGradient(colors: memory.pastel, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("\u{201C}")
                    .font(Typo.serif(120))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: Color(hex: 0x50323C).opacity(0.2), radius: 6, y: 1)
        }
    }

    // MARK: editorial sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(metaLine)
                .font(Typo.mono(11))
                .tracking(1.5)
                .foregroundStyle(Color(hex: 0xB3A591))

            Text(memory.title)
                .font(Typo.serif(36))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if memory.kind == .citation, let quote = memory.note {
                Text(quote)
                    .font(Typo.serif(26))
                    .foregroundStyle(Palette.inkSoft)
            } else if let note = memory.note {
                Text(note)
                    .font(Typo.sans(15))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if memory.kind == .voice {
                VoicePlayerView(duration: memory.audio ?? "0:00", caption: "la voix de \(child.name)", audioData: memory.audioData)
            }

            if memory.kind == .milestone {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").foregroundStyle(Palette.vert)
                    Text("Jalon").font(Typo.serif(15)).foregroundStyle(Palette.ink)
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
/// Plays the decrypted audio blob with AVAudioPlayer when present
/// (DESIGN_INTEGRATION.md §5 — on-device only, never a cloud speech API); falls
/// back to a simulated progress for sample memories that carry no blob.
struct VoicePlayerView: View {
    let duration: String
    let caption: String
    var audioData: Data?

    @State private var progress: Double = 0
    @State private var playing = false
    @State private var player: AVAudioPlayer?

    private let bars: [CGFloat] = [10, 18, 26, 14, 30, 22, 34, 20, 28, 16, 24, 12, 22, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: toggle) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(Typo.sans(15))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Palette.accent, in: Circle())
                }
                waveform
                Text(duration)
                    .font(Typo.mono(11))
                    .foregroundStyle(Palette.muted)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(caption)
                .font(Typo.sans(12))
                .foregroundStyle(Color(hex: 0xA89C8E))
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in tick() }
        .onDisappear { player?.stop() }
    }

    private func toggle() {
        if audioData == nil {
            playing.toggle() // simulated
            return
        }
        if player == nil, let data = audioData {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: data)
            player?.prepareToPlay()
        }
        guard let p = player else { return }
        if p.isPlaying { p.pause(); playing = false } else { p.play(); playing = true }
    }

    private func tick() {
        guard playing else { return }
        if let p = player {
            progress = p.duration > 0 ? p.currentTime / p.duration : 0
            if !p.isPlaying { playing = false; progress = 0 } // reached the end
        } else {
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
