import SwiftUI

@main
struct FreshlyApp: App {
    @State private var store: AppListStore

    init() {
        let store = AppListStore()
        store.refresh()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 720, height: 480)

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            if store.outdatedCount > 0 {
                Text("\(Image(systemName: "arrow.triangle.2.circlepath")) \(store.outdatedCount)")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }
}
