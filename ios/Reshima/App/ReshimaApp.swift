import SwiftUI

@main
struct ReshimaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ShoppingStore()

    var body: some Scene {
        WindowGroup {
            ShoppingListView(store: store)
                .environment(\.layoutDirection, store.language.isRTL ? .rightToLeft : .leftToRight)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Catch up immediately when the app returns to the foreground.
            if newPhase == .active {
                store.requestSync()
            }
        }
    }
}
