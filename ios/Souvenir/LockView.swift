import SwiftUI
import LocalAuthentication

/// Entry ritual (DESIGN_INTEGRATION §9): unlock with Face ID / Touch ID before
/// anything is shown. There is no "skip" path (SECURITY.md §6.3); biometrics
/// merely unlock a key already on the device (§3). Falls back to the device
/// passcode (deviceOwnerAuthentication) so the user is never hard-locked-out
/// (§6.3 — no self-inflicted DoS), but never bypassed.
struct LockView: View {
    let onUnlock: () -> Void
    @State private var checking = false

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.circle")
                    .font(.system(size: 46))
                    .foregroundStyle(Palette.accent)
                Text("Tes souvenirs sont à l'abri")
                    .font(Typo.serif(30))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Déverrouille pour entrer.")
                    .font(Typo.sans(15))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Button(action: authenticate) {
                    Label("Déverrouiller", systemImage: "faceid")
                        .font(Typo.sans(17, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 100))
                }
                .disabled(checking)
            }
            .padding(32)
        }
        .task { authenticate() }
    }

    private func authenticate() {
        guard !checking else { return }
        checking = true
        let context = LAContext()
        context.localizedFallbackTitle = "Utiliser le code"
        let reason = "Déverrouille tes souvenirs"
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            checking = false // no biometrics/passcode available → stays locked, no bypass
            return
        }
        context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                checking = false
                if success { onUnlock() }
            }
        }
    }
}
