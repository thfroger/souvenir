import Foundation
import CryptoCore

/// Drives the social-recovery setup flow (SECURITY.md §5). The crypto and the
/// persistence are real: `MemoryStore.setupSocialRecovery` generates a Recovery
/// Key, wraps the same MIK the passphrase does, Shamir 2-of-3-splits the RK, and
/// publishes only the opaque `MIK-under-RK` + `VK-under-MIK` — the shares come
/// back here to be handed to the guardians and never touch the server.
///
/// What this skeleton does NOT do yet (infra, not this screen): deliver each
/// share into the guardian's own app / encrypted channel (§5). Here the shares
/// are shown for the user to hand off out-of-band.
@MainActor
final class RecoverySetupModel: ObservableObject {
    struct Guardian: Identifiable, Equatable {
        let id = UUID()
        var name: String = ""
    }

    let childName: String
    private let store: MemoryStore
    @Published var guardians: [Guardian] = [Guardian(), Guardian(), Guardian()]
    @Published private(set) var isSealed = false
    @Published private(set) var sealing = false
    @Published var errorMessage: String?

    /// One portable share string per guardian, in the same order. Shown so the
    /// user can hand each to its guardian; never logged, never sent to the server.
    @Published private(set) var shareStrings: [String] = []

    init(childName: String, store: MemoryStore) {
        self.childName = childName
        self.store = store
    }

    var trimmedNames: [String] {
        guardians.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// All three named, and distinct (you cannot lean on the same person twice).
    var canSeal: Bool {
        let names = trimmedNames
        return names.allSatisfy { !$0.isEmpty } && Set(names).count == names.count
    }

    func seal() async {
        guard canSeal, !sealing else { return }
        sealing = true
        defer { sealing = false }
        switch await store.setupSocialRecovery() {
        case .success(let shares):
            shareStrings = shares.map(MemoryStore.encodeShare)
            errorMessage = nil
            isSealed = true
        case .noKey:
            errorMessage = "La clé de ton coffre n'est pas disponible sur cet appareil."
        case .offline:
            errorMessage = "Impossible de joindre le coffre. Réessaie une fois connectée."
        case .failed:
            errorMessage = "Le filet n'a pas pu être tissé. Réessaie."
        }
    }
}
