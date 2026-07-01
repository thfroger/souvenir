import SwiftUI
import UIKit

/// The Frise (home, level 1) — DESIGN.md §3.A, recreated hi-fi.
/// Header · child selector · surprise card · "cette semaine" timeline · glass bar.
struct FriseView: View {
    @EnvironmentObject private var store: MemoryStore
    @Binding var selectedChildID: UUID
    @Binding var openedMemory: Memory?
    @State private var showSettings = false
    @State private var showSync = false

    private var child: Child {
        SampleData.children.first { $0.id == selectedChildID } ?? SampleData.lea
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    keyWarning
                    childSelector
                    Button {
                        withAnimation(.easeInOut(duration: 0.7)) {
                            openedMemory = surpriseAsMemory(SampleData.surprise(for: child))
                        }
                    } label: {
                        SurpriseCard(surprise: SampleData.surprise(for: child))
                    }
                    .buttonStyle(.plain)
                    Text("CETTE SEMAINE")
                        .font(Typo.mono(11))
                        .tracking(2)
                        .foregroundStyle(Palette.muted)
                    timeline
                    Color.clear.frame(height: 88) // room for the floating bar
                }
                .padding(.horizontal, 26)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showSettings) {
            // The header sliders button is the Réglages hub (DESIGN_INTEGRATION §9):
            // social recovery + (DEBUG) the dev server URL.
            SettingsView(childName: child.name) { showSettings = false }
                .environmentObject(store)
        }
        .sheet(isPresented: $showSync) {
            VaultSyncView(start: .recover) { showSync = false }
                .environmentObject(store)
        }
    }

    /// The surprise is shown immersively as a memory from `yearsAgo` back.
    private func surpriseAsMemory(_ s: Surprise) -> Memory {
        Memory(childID: child.id, kind: .photo, daysAgo: 365 * s.yearsAgo,
               title: s.title, note: s.subtitle, audio: nil, pastel: s.pastel)
    }

    // MARK: key-unavailable banner

    // Honest signal instead of a silently-empty Frise: when entries exist but
    // can't be decrypted, say so (and why), rather than dropping them in silence.
    @ViewBuilder private var keyWarning: some View {
        let n = store.unreadableCount
        if n > 0 {
            let plural = n > 1
            VStack(alignment: .leading, spacing: 6) {
                Label("\(n) souvenir\(plural ? "s" : "") illisible\(plural ? "s" : "")",
                      systemImage: "lock.trianglebadge.exclamationmark")
                    .font(Typo.sans(14.5, .medium))
                    .foregroundStyle(brick)
                Text(store.keyState == .unavailable
                     ? "La clé de ce coffre est introuvable sur cet appareil. Ces souvenirs restent à l'abri, mais ne peuvent pas être déchiffrés ici — et aucune copie de la clé n'existe ailleurs, c'est ce qui les protège."
                     : "Leur clé de déchiffrement est indisponible sur cet appareil.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showSync = true } label: {
                    Text("Saisir ma phrase de récupération")
                        .font(Typo.sans(13, .semibold))
                        .foregroundStyle(brick)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(brick.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(brick.opacity(0.28), lineWidth: 1))
        }
    }

    private var brick: Color { Color(red: 0.62, green: 0.26, blue: 0.22) }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(todayLabel)
                    .font(Typo.mono(12))
                    .tracking(2)
                    .foregroundStyle(Palette.muted)
                Text("Bonjour, Camille")
                    .font(Typo.serif(30))
                    .foregroundStyle(Palette.ink)
                syncStatus
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 40, height: 40)
                    .background(Palette.chip, in: Circle())
            }
        }
    }

    // Tender sync affordance (DESIGN_INTEGRATION §8) — care, not an anxious spinner.
    private var syncStatus: some View {
        let s = syncLabel
        return Label(s.text, systemImage: s.icon)
            .font(Typo.mono(10))
            .tracking(1)
            .foregroundStyle(s.color)
            .padding(.top, 2)
    }

    private var syncLabel: (text: String, icon: String, color: Color) {
        if store.syncing { return ("synchronisation…", "arrow.triangle.2.circlepath", Palette.muted) }
        if store.pendingSyncCount == 0 { return ("à l'abri", "checkmark.icloud", Palette.accent) }
        return ("\(store.pendingSyncCount) en attente", "icloud.slash", Palette.faint)
    }

    // MARK: child selector

    private var childSelector: some View {
        HStack(spacing: 10) {
            ForEach(SampleData.children) { c in
                let active = c.id == selectedChildID
                Button { selectedChildID = c.id } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LinearGradient(colors: c.avatar, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Text(c.name).font(Typo.sans(15, .medium))
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .padding(.leading, 6)
                    .foregroundStyle(active ? .white : Palette.muted)
                    .background(active ? Palette.ink : Palette.chip, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "plus")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Palette.divider, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
            Spacer()
        }
    }

    // MARK: timeline

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(store.memories(for: child)) { memory in
                TimelineRow(memory: memory) { withAnimation(.easeInOut(duration: 0.7)) { openedMemory = memory } }
            }
        }
    }
}

// MARK: - Surprise card

struct SurpriseCard: View {
    let surprise: Surprise

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoPlaceholder(colors: surprise.pastel)
                .frame(height: 188)
                .overlay(alignment: .topLeading) {
                    Text(surprise.badge)
                        .font(Typo.mono(10))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(surprise.caption)
                        .font(Typo.mono(10))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(surprise.title)
                    .font(Typo.serif(24))
                    .foregroundStyle(Palette.ink)
                Text(surprise.subtitle)
                    .font(Typo.sans(13.5))
                    .foregroundStyle(Color(hex: 0x7A7280))
            }
            .padding(18)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x50323C).opacity(0.18), radius: 15, x: 0, y: 10)
    }
}

// MARK: - Timeline row

struct TimelineRow: View {
    let memory: Memory
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) { row }.buttonStyle(.plain)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 14) {
            // rail: continuous vertical line + colored dot
            ZStack(alignment: .top) {
                Rectangle().fill(Palette.divider).frame(width: 1.5)
                Circle().fill(memory.kind.dot).frame(width: 11, height: 11).padding(.top, 3)
            }
            .frame(width: 11)

            VStack(alignment: .leading, spacing: 8) {
                Text(memory.dateLabel)
                    .font(Typo.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Palette.faint)
                content
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder private var content: some View {
        if memory.kind == .citation {
            HStack(alignment: .top, spacing: 12) {
                Text("\u{201C}")
                    .font(Typo.serif(52))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .frame(height: 26, alignment: .top)
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.note ?? "")
                        .font(Typo.serif(19))
                        .foregroundStyle(Palette.ink)
                    Text(memory.title)
                        .font(Typo.mono(12))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: memory.pastel.map { $0.opacity(0.5) },
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            HStack(spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.title)
                        .font(Typo.serif(19))
                        .foregroundStyle(Palette.ink)
                    Text(metaLine)
                        .font(Typo.mono(12))
                        .tracking(1)
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var metaLine: String {
        if let audio = memory.audio { return "\(memory.kind.meta) · \(audio)" }
        return memory.kind.meta
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = memory.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if memory.kind.hasPhoto {
            PhotoPlaceholder(colors: memory.pastel)
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: memory.pastel, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 66, height: 66)
                .overlay {
                    if let icon = memory.kind.icon {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
        }
    }
}

// MARK: - Photo placeholder (pastel gradient + diagonal stripes, README.md §2)

struct PhotoPlaceholder: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(DiagonalStripes())
    }
}

struct DiagonalStripes: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 32
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(p, with: .color(.white.opacity(0.14)), lineWidth: 16)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Floating glass bottom bar (the ONLY glass element, DESIGN.md §2)

struct GlassBottomBar: View {
    @Binding var tab: ContentView.Tab
    var onAdd: () -> Void = {}

    var body: some View {
        HStack {
            Button { tab = .frise } label: {
                Text("Frise")
                    .font(Typo.serif(16))
                    .foregroundStyle(tab == .frise ? Palette.ink : Palette.faint)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Palette.ink, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button { tab = .arbre } label: {
                Text("Ciel")
                    .font(Typo.serif(16))
                    .foregroundStyle(tab == .arbre ? Palette.ink : Palette.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: Color(hex: 0x50323C).opacity(0.18), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 48)
        .padding(.bottom, 6)
    }
}

#Preview {
    FriseView(selectedChildID: .constant(SampleData.lea.id), openedMemory: .constant(nil))
        .environmentObject(MemoryStore())
}
