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
    @State private var text = ""
    @State private var title = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: Data?
    @FocusState private var focused: Bool

    private var heading: String {
        switch kind {
        case .photo: return "Une photo"
        case .measure: return "Une mesure"
        default: return "Une petite phrase"
        }
    }

    private var canSave: Bool {
        kind == .photo ? pickedImage != nil : !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                if kind == .photo { photoField } else { textFields }

                Spacer()

                Button(action: save) {
                    Text("Garder ce souvenir")
                        .font(Typo.sans(17, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Palette.ink : Palette.muted, in: RoundedRectangle(cornerRadius: 100))
                }
                .disabled(!canSave)
            }
            .padding(28)
        }
        .onAppear { if kind != .photo { focused = true } }
    }

    private var header: some View {
        HStack {
            Text(heading).font(Typo.serif(30)).foregroundStyle(Palette.ink)
            Spacer()
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
        TextField(kind == .measure ? "ex. 78 cm" : "« ce qu'iel a dit »", text: $text, axis: .vertical)
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

    private var photoField: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                if let data = pickedImage, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Palette.paperAlt)
                    VStack(spacing: 10) {
                        Image(systemName: "camera").font(.system(size: 28)).foregroundStyle(Palette.bleu)
                        Text("Choisir une photo").font(Typo.sans(15)).foregroundStyle(Palette.muted)
                    }
                }
            }
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.divider, lineWidth: 1))
        }
        .onChange(of: pickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    pickedImage = data
                }
            }
        }
    }

    private func save() {
        switch kind {
        case .citation: store.addCitation(childID: childID, quote: text, title: title)
        case .measure: store.addMeasure(childID: childID, value: text)
        case .photo: if let data = pickedImage { store.addPhoto(childID: childID, imageData: data) }
        default: break
        }
        onClose()
    }
}
