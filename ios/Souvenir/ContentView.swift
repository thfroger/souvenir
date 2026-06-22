import SwiftUI

/// App root. The joyful core starts at the Frise (DESIGN.md §3.A); the crypto
/// core stays isolated behind it (SECURITY.md §1.5) and is reached through the
/// flows (e.g. social recovery via the header sliders / Réglages hub).
struct ContentView: View {
    var body: some View {
        FriseView()
    }
}

#Preview {
    ContentView()
}
