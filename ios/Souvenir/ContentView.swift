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
    @State private var openedMemory: Memory?

    private var child: Child {
        SampleData.children.first { $0.id == childID } ?? SampleData.lea
    }

    // The immersive view that a tapped souvenir opens into (DESIGN.md §3.B). It
    // animates gently over a slow curve instead of the abrupt system slide.
    private static let immersiveAnim: Animation = .easeInOut(duration: 0.5)

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .frise: FriseView(selectedChildID: $childID, openedMemory: $openedMemory)
            case .arbre: ArbreView(childID: childID, openedMemory: $openedMemory)
            }
            GlassBottomBar(tab: $tab) { showAdd = true }

            if let memory = openedMemory {
                let memChild = SampleData.children.first { $0.id == memory.childID } ?? child
                ImmersiveMemoryView(memory: memory, child: memChild) {
                    withAnimation(Self.immersiveAnim) { openedMemory = nil }
                }
                .ignoresSafeArea()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .environmentObject(store)
        .sheet(isPresented: $showAdd, onDismiss: {
            if let k = pendingKind { pendingKind = nil; captureKind = k }
        }) {
            AddSheetView(childName: child.name) { kind in
                pendingKind = kind // all six types are wired
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
