import SwiftUI

// Presentation models for the Frise. In the real app these come from *decrypted*
// memories filtered locally by child (DESIGN_INTEGRATION.md §2/§10); here they are
// in-memory placeholders. No `liked` field (removed from scope, §6).

struct Child: Identifiable {
    let id = UUID()
    let name: String
    let birthYear: Int
    let avatar: [Color] // two-pastel gradient
}

enum MemoryKind: Identifiable {
    case photo, voice, citation, milestone, measure, drawing

    var id: Self { self }

    var meta: String {
        switch self {
        case .photo: return "PHOTO"
        case .voice: return "NOTE VOCALE"
        case .citation: return "CITATION"
        case .milestone: return "JALON"
        case .measure: return "MESURE"
        case .drawing: return "DESSIN"
        }
    }

    /// Colored dot on the timeline rail (color = type).
    var dot: Color {
        switch self {
        case .photo: return Palette.bleu
        case .voice: return Palette.peche
        case .citation: return Palette.lilas
        case .milestone: return Palette.vert
        case .measure: return Palette.jaune
        case .drawing: return Palette.rose
        }
    }

    /// Line icon for non-photo thumbnails (no emoji — SF Symbols stand in for
    /// the Lucide/Feather set until it is bundled).
    var icon: String? {
        switch self {
        case .photo, .drawing: return nil
        case .voice: return "waveform"
        case .citation: return nil
        case .milestone: return "leaf"
        case .measure: return "ruler"
        }
    }

    var hasPhoto: Bool { self == .photo || self == .drawing }
}

struct Memory: Identifiable {
    let id = UUID()
    let childID: UUID
    let kind: MemoryKind
    let daysAgo: Int
    let title: String
    let note: String?   // short preview, or the quote for a citation
    let audio: String?  // duration label, e.g. "0:42"
    let pastel: [Color] // gradient for the photo placeholder / thumbnail tint
    let imageData: Data? // decrypted image for display (nil → pastel placeholder)
    let audioData: Data? // decrypted audio for playback (nil → simulated)

    init(childID: UUID, kind: MemoryKind, daysAgo: Int, title: String,
         note: String?, audio: String?, pastel: [Color],
         imageData: Data? = nil, audioData: Data? = nil) {
        self.childID = childID
        self.kind = kind
        self.daysAgo = daysAgo
        self.title = title
        self.note = note
        self.audio = audio
        self.pastel = pastel
        self.imageData = imageData
        self.audioData = audioData
    }

    var date: Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"
        return f.string(from: date).uppercased()
    }
}

struct Surprise {
    let yearsAgo: Int
    let title: String
    let subtitle: String
    let caption: String
    let pastel: [Color]

    var badge: String { "IL Y A \(yearsAgo) ANS · AUJOURD'HUI" }
}

enum SampleData {
    static let lea = Child(name: "Léa", birthYear: 2021, avatar: [Palette.rose, Palette.lilas])
    static let noe = Child(name: "Noé", birthYear: 2023, avatar: [Palette.bleu, Palette.vert])
    static let children = [lea, noe]

    static func surprise(for child: Child) -> Surprise {
        if child.id == noe.id {
            return Surprise(yearsAgo: 1, title: "Le premier rire",
                            subtitle: "Dans le salon, au réveil.", caption: "JUIN ’25",
                            pastel: [Palette.bleu, Palette.vert])
        }
        return Surprise(yearsAgo: 3, title: "Les premiers pas",
                        subtitle: "Au parc, un mardi de juin.", caption: "JUIN ’23",
                        pastel: [Palette.peche, Palette.jaune])
    }

    static func memories(for child: Child) -> [Memory] {
        if child.id == noe.id {
            return [
                Memory(childID: noe.id, kind: .photo, daysAgo: 1, title: "Au bord de l'eau",
                       note: "Les pieds dans le sable pour la première fois.", audio: nil,
                       pastel: [Palette.bleu, Palette.vert]),
                Memory(childID: noe.id, kind: .citation, daysAgo: 2, title: "Le premier mot",
                       note: "« encore »", audio: nil, pastel: [Palette.lilas, Palette.rose]),
                Memory(childID: noe.id, kind: .voice, daysAgo: 4, title: "Son grand rire",
                       note: nil, audio: "0:18", pastel: [Palette.peche, Palette.jaune]),
            ]
        }
        return [
            Memory(childID: lea.id, kind: .citation, daysAgo: 0, title: "Le premier mot",
                   note: "« papa »", audio: nil, pastel: [Palette.lilas, Palette.rose]),
            Memory(childID: lea.id, kind: .voice, daysAgo: 1, title: "La voix de Léa",
                   note: nil, audio: "0:42", pastel: [Palette.peche, Palette.jaune]),
            Memory(childID: lea.id, kind: .photo, daysAgo: 3, title: "Au bord de l'eau",
                   note: "Elle a voulu toucher chaque vague.", audio: nil,
                   pastel: [Palette.bleu, Palette.vert]),
            Memory(childID: lea.id, kind: .milestone, daysAgo: 4, title: "Première dent",
                   note: nil, audio: nil, pastel: [Palette.vert, Palette.jaune]),
            Memory(childID: lea.id, kind: .measure, daysAgo: 6, title: "78 cm",
                   note: "Déjà si grande.", audio: nil, pastel: [Palette.jaune, Palette.peche]),
        ]
    }
}
