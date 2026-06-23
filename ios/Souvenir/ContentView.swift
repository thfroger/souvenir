import SwiftUI

/// App root: the two level-1 screens (Frise / Arbre) share the selected child
/// and the floating glass bottom bar (DESIGN.md §4). The ＋ opens the Ajout
/// sheet (écran D). The crypto core stays isolated behind the UI (SECURITY.md
/// §1.5), reached through the flows.
struct ContentView: View {
    enum Tab { case frise, arbre }

    @State private var tab: Tab = .frise
    @State private var childID = SampleData.lea.id
    @State private var showAdd = false

    private var childName: String {
        (SampleData.children.first { $0.id == childID } ?? SampleData.lea).name
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .frise: FriseView(selectedChildID: $childID)
            case .arbre: ArbreView(childID: childID)
            }
            GlassBottomBar(tab: $tab) { showAdd = true }
        }
        .sheet(isPresented: $showAdd) {
            AddSheetView(childName: childName) { showAdd = false }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.paper)
                .presentationCornerRadius(28)
        }
    }
}

#Preview {
    ContentView()
}
