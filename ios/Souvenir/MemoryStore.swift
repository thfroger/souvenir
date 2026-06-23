import SwiftUI
import UIKit
import CryptoCore

/// Re-encodes an image to JPEG, which drops EXIF/GPS metadata (SECURITY.md §8.1),
/// and bounds its dimensions. A rigorous strip would use ImageIO; UIImage
/// re-encoding is an effective, simple equivalent for the skeleton.
enum ImageTools {
    static func stripExifJPEG(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// A minimal on-device memory store that exercises the real crypto path
/// (SECURITY.md §3): each entry's text content is encrypted with a per-entry
/// data key (DEK), itself wrapped under a vault key (VK). The Frise/Arbre read
/// decrypted `Memory` values from here.
///
/// Scope of this slice: in-memory only, VK generated per launch. Persistence
/// (VK in the Keychain, encrypted blobs on disk) and server upload are the next
/// step — but the encrypt → wrap → unwrap → decrypt round-trip is real, not faked.
@MainActor
final class MemoryStore: ObservableObject {
    private struct Content: Codable { let title: String; let note: String? }

    private struct Entry: Identifiable {
        let id = UUID()
        let childID: UUID
        let kind: MemoryKind
        let createdAt: Date
        let pastel: [Color]
        let audio: String?
        let sealed: AEAD.Sealed       // encrypted Content
        let sealedImage: AEAD.Sealed? // encrypted image blob (same DEK), if any
        let wrappedKey: WrappedKey    // per-entry DEK wrapped under the VK
    }

    private let vaultKey: SymmetricKey
    @Published private var entries: [Entry] = []

    init() {
        vaultKey = (try? VaultKey.generate()) ?? ((try? SymmetricKey(bytes: [UInt8](repeating: 0, count: 32))) ?? Self.placeholderKey)
        seedFromSamples()
    }

    // MARK: read

    func memories(for child: Child) -> [Memory] {
        entries
            .filter { $0.childID == child.id }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { decrypt($0) }
    }

    // MARK: write

    func addCitation(childID: UUID, quote: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        add(childID: childID, kind: .citation,
            title: t.isEmpty ? "Citation" : t,
            note: "« \(quote.trimmingCharacters(in: .whitespacesAndNewlines)) »",
            pastel: [Palette.lilas, Palette.rose])
    }

    func addMeasure(childID: UUID, value: String) {
        add(childID: childID, kind: .measure,
            title: value.trimmingCharacters(in: .whitespacesAndNewlines),
            note: nil,
            pastel: [Palette.jaune, Palette.peche])
    }

    // MARK: crypto core path

    private func add(childID: UUID, kind: MemoryKind, title: String, note: String?,
                     pastel: [Color], audio: String? = nil, image: Data? = nil, createdAt: Date = Date()) {
        guard let payload = try? JSONEncoder().encode(Content(title: title, note: note)) else { return }
        do {
            let dek = try DataKey.generate()
            let sealed = try AEAD.seal(Array(payload), key: dek.bytes)
            let sealedImage = try image.map { try AEAD.seal(Array($0), key: dek.bytes) }
            let wrapped = try KeyWrap.wrap(dek, under: vaultKey)
            entries.append(Entry(childID: childID, kind: kind, createdAt: createdAt,
                                 pastel: pastel, audio: audio, sealed: sealed,
                                 sealedImage: sealedImage, wrappedKey: wrapped))
        } catch {
            // A failed encrypt must never surface a half-written entry (SECURITY.md §1.6).
        }
    }

    func addPhoto(childID: UUID, imageData: Data) {
        guard let stripped = ImageTools.stripExifJPEG(imageData) else { return }
        add(childID: childID, kind: .photo, title: "Photo", note: nil,
            pastel: [Palette.bleu, Palette.vert], image: stripped)
    }

    private func decrypt(_ e: Entry) -> Memory? {
        guard
            let dek = try? KeyWrap.unwrap(e.wrappedKey, with: vaultKey),
            let plain = try? AEAD.open(e.sealed, key: dek.bytes),
            let content = try? JSONDecoder().decode(Content.self, from: Data(plain))
        else { return nil }

        let days = max(0, Calendar.current.dateComponents([.day], from: e.createdAt, to: Date()).day ?? 0)
        let image = e.sealedImage.flatMap { try? AEAD.open($0, key: dek.bytes) }.map { Data($0) }
        return Memory(childID: e.childID, kind: e.kind, daysAgo: days,
                      title: content.title, note: content.note, audio: e.audio,
                      pastel: e.pastel, imageData: image)
    }

    // MARK: seed (encrypt the sample memories so the Frise has content)

    private func seedFromSamples() {
        for child in SampleData.children {
            for m in SampleData.memories(for: child) {
                add(childID: child.id, kind: m.kind, title: m.title, note: m.note,
                    pastel: m.pastel, audio: m.audio, createdAt: m.date)
            }
        }
    }

    private static let placeholderKey = try! SymmetricKey(bytes: [UInt8](repeating: 1, count: 32))
}
