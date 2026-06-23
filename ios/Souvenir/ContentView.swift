import SwiftUI

/// App root: the two level-1 screens (Frise / Arbre) share the selected child,
/// the memory store, and the floating glass bottom bar (DESIGN.md §4). The ＋
/// opens the Ajout sheet (écran D); picking a text type opens capture.
struct ContentView: View {
    enum Tab { case frise, arbre }

    @StateObject private var store = MemoryStore()
    @State private var tab: Tab = .frise
    @State private var childID = SampleData.lea.id
    @State private var showAdd = false
    @State private var pendingKind: MemoryKind?
    @State private var captureKind: MemoryKind?

    private var child: Child {
        SampleData.children.first { $0.id == childID } ?? SampleData.lea
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .frise: FriseView(selectedChildID: $childID)
            case .arbre: ArbreView(childID: childID)
            }
            GlassBottomBar(tab: $tab) { showAdd = true }
        }
        // Fixed light "paper" aesthetic (DESIGN.md §2): no dark mode is designed,
        // so the system materials (the glass bar, the immersive back button) must
        // not flip dark on a device set to Dark Mode.
        .preferredColorScheme(.light)
        .environmentObject(store)
        .sheet(isPresented: $showAdd, onDismiss: {
            if let k = pendingKind { pendingKind = nil; captureKind = k }
        }) {
            AddSheetView(childName: child.name) { kind in
                // Wired: citation, mesure, photo, note vocale. Jalon/dessin come next.
                if kind != .milestone && kind != .drawing { pendingKind = kind }
                showAdd = false
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Palette.paper)
            .presentationCornerRadius(28)
        }
        .sheet(item: $captureKind) { kind in
            CaptureView(kind: kind, childID: childID, childName: child.name) { captureKind = nil }
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationBackground(Palette.paper)
        }
    }
}

#Preview {
    ContentView()
}
