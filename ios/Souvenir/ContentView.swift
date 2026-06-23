import SwiftUI

/// App root: the two level-1 screens (Frise / Arbre) share the selected child
/// and the floating glass bottom bar (DESIGN.md §4). The crypto core stays
/// isolated behind the UI (SECURITY.md §1.5), reached through the flows.
struct ContentView: View {
    enum Tab { case frise, arbre }

    @State private var tab: Tab = .frise
    @State private var childID = SampleData.lea.id

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .frise: FriseView(selectedChildID: $childID)
            case .arbre: ArbreView(childID: childID)
            }
            GlassBottomBar(tab: $tab)
        }
    }
}

#Preview {
    ContentView()
}
