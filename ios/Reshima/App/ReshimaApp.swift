import SwiftUI

@main
struct ReshimaApp: App {
    @State private var store = ShoppingStore()

    var body: some Scene {
        WindowGroup {
            ShoppingListView(store: store)
                .environment(\.layoutDirection, store.language.isRTL ? .rightToLeft : .leftToRight)
        }
    }
}
