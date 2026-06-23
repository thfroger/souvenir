import SwiftUI

/// Gates the app behind the biometric unlock ritual. ContentView (and its store,
/// hence any vault-key access) is only created once unlocked — biometrics unlock
/// the local key (SECURITY.md §3), with no skip path (§6.3).
struct RootView: View {
    @State private var unlocked = false

    var body: some View {
        Group {
            if unlocked {
                ContentView()
            } else {
                LockView { unlocked = true }
            }
        }
        // Fixed light "paper" aesthetic (DESIGN.md §2) — no dark mode.
        .preferredColorScheme(.light)
    }
}

#Preview {
    RootView()
}
