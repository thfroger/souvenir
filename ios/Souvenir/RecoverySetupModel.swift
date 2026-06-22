import Foundation
import CryptoCore

/// Drives the social-recovery setup flow (SECURITY.md §5). The crypto is real:
/// sealing generates a Recovery Key, splits it 2-of-3 through CryptoCore, and
/// re-checks that any two shares reconstruct it before claiming success.
///
/// What this skeleton does NOT do yet (infra, not this screen):
/// - persist anything: the RK must never be stored in cleartext; in a real build
///   it wraps the MIK and only `MIK-wrapped-under-RK` is kept (§5).
/// - deliver shares: each share goes to its guardian out-of-band / encrypted,
///   ideally into the guardian's own app (§5). Here shares are held in memory only.
@MainActor
final class RecoverySetupModel: ObservableObject {
    struct Guardian: Identifiable, Equatable {
        let id = UUID()
        var name: String = ""
    }

    let childName: String
    @Published var guardians: [Guardian] = [Guardian(), Guardian(), Guardian()]
    @Published private(set) var isSealed = false
    @Published var errorMessage: String?

    /// Held only in memory, only for the lifetime of this flow. Never rendered,
    /// never logged.
    private var shares: [Shamir.Share]?

    init(childName: String) {
        self.childName = childName
    }

    var trimmedNames: [String] {
        guardians.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// All three named, and distinct (you cannot lean on the same person twice).
    var canSeal: Bool {
        let names = trimmedNames
        return names.allSatisfy { !$0.isEmpty } && Set(names).count == names.count
    }

    func seal() {
        guard canSeal else { return }
        do {
            let rk = try RecoveryKey.generate()
            let split = try Shamir.split(secret: rk.bytes, threshold: 2, shares: 3)

            // Self-check: any two shares must reconstruct the RK before we tell the
            // user the net holds. (Mirror of the production re-decryption self-check
            // ethos, SECURITY.md §1.6.)
            let recovered = try SymmetricKey(bytes: try Shamir.combine([split[0], split[2]]))
            guard recovered == rk else {
                errorMessage = "Le filet n'a pas pu être vérifié. Réessaie."
                return
            }

            shares = split
            errorMessage = nil
            isSealed = true
        } catch {
            errorMessage = "Le filet n'a pas pu être tissé (\(error))."
        }
    }
}
