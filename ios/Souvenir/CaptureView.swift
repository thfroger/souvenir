import SwiftUI
import PhotosUI
import UIKit

/// Capture for the types wired so far: Citation, Mesure (text) and Photo
/// (PhotosPicker). On save the content is encrypted through the store
/// (CryptoCore) and appears in the Frise. Note vocale / Jalon / Dessin come next.
struct CaptureView: View {
    let kind: MemoryKind
    let childID: UUID
    let childName: String
    let onClose: () -> Void

    @EnvironmentObject private var store: MemoryStore
    @StateObject private var recorder = AudioRecorder()
    @State private var text = ""
    @State private var title = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: Data?
    @FocusState private var focused: Bool

    private var heading: String {
        switch kind {
        case .photo: return "Une photo"
        case .drawing: return "Un dessin"
        case .voice: return "Une note vocale"
        case .measure: return "Une mesure"
        case .milestone: return "Un jalon"
        default: return "Une petite phrase"
        }
    }

    private var canSave: Bool {
        switch kind {
        case .photo, .drawing: return pickedImage != nil
        case .voice: return recorder.finishedURL != nil
        default: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var textPlaceholder: String {
        switch kind {
        case .measure: return "ex. 78 cm"
        case .milestone: return "ex. Première dent"
        default: return "« ce qu'iel a dit »"
        }
    }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                header
                Text("DE \(childName.uppercased()) — AUJOURD'HUI")
                    .font(Typo.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Palette.faint)

                switch kind {
                case .photo, .drawing: photoField
                case .voice: voiceField
                default: textFields // citation, measure, milestone
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(action: save) {
                        Text("Garder")
                            .font(Typo.sans(16, .medium))
                            .foregroundStyle(.white)
                            .padding(.vertical, 13)
                            .padding(.horizontal, 34)
                            .background(canSave ? Palette.ink : Palette.muted, in: Capsule())
                    }
                    .disabled(!canSave)
                    Spacer()
                }
            }
            .padding(28)
        }
        .onAppear { if kind == .citation || kind == .measure { focused = true } }
    }

    private var voiceField: some View {
        VStack(spacing: 16) {
            Button { recorder.toggle() } label: {
                ZStack {
                    Circle().fill(recorder.isRecording ? Palette.accent : Palette.ink)
                        .frame(width: 76, height: 76)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Text(statusLabel)
                .font(Typo.mono(12))
                .foregroundStyle(Palette.muted)

            if recorder.permissionDenied {
                Text("Micro refusé — autorise-le dans Réglages.")
                    .font(Typo.sans(13))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.divider, lineWidth: 1))
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in recorder.refresh() }
    }

    private var statusLabel: String {
        if recorder.isRecording { return "● ENREGISTREMENT · \(recorder.durationLabel)" }
        if recorder.finishedURL != nil { return "ENREGISTRÉ · \(recorder.durationLabel)" }
        return "TOUCHEZ POUR ENREGISTRER"
    }

    private var header: some View {
        HStack {
            Text(heading)
                .font(Typo.serif(30))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 34, height: 34)
                    .background(Palette.chip, in: Circle())
            }
        }
    }

    @ViewBuilder private var textFields: some View {
        TextField(textPlaceholder, text: $text, axis: .vertical)
            .font(kind == .citation ? Typo.serif(22) : Typo.sans(20))
            .foregroundStyle(Palette.ink)
            .focused($focused)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.divider, lineWidth: 1))

        if kind == .citation {
            TextField("Titre (optionnel)", text: $title)
                .font(Typo.sans(15))
                .foregroundStyle(Palette.inkSoft)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder private var photoField: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            // A bounded container so a scaledToFill image fills it as an overlay
            // instead of driving (and overflowing) the layout width.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .overlay {
                    if let data = pickedImage, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: kind == .drawing ? "scribble.variable" : "camera").font(.system(size: 28)).foregroundStyle(Palette.bleu)
                            Text(kind == .drawing ? "Choisir un dessin" : "Choisir une photo").font(Typo.sans(15)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .background(Palette.paperAlt)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.divider, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: pickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    pickedImage = data
                }
            }
        }

        TextField("Un titre (optionnel)", text: $title)
            .font(Typo.sans(15))
            .foregroundStyle(Palette.inkSoft)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        switch kind {
        case .citation: store.addCitation(childID: childID, quote: text, title: title)
        case .measure: store.addMeasure(childID: childID, value: text)
        case .milestone: store.addMilestone(childID: childID, label: text)
        case .photo: if let data = pickedImage { store.addPhoto(childID: childID, imageData: data, title: title) }
        case .drawing: if let data = pickedImage { store.addPhoto(childID: childID, imageData: data, kind: .drawing, title: title) }
        case .voice: if let data = recorder.recordedData() { store.addVoice(childID: childID, audioData: data, duration: recorder.durationLabel) }
        }
        onClose()
    }
}
