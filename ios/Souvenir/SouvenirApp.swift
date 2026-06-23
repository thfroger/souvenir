import SwiftUI

@main
struct SouvenirApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
