import SwiftUI

@main
struct FreshlyApp: App {
    @State private var store: AppListStore

    init() {
        let store = AppListStore()
        store.refresh(origin: .automatic)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 720, height: 480)

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Group {
                if store.outdatedCount > 0 {
                    Text("\(Image(systemName: "arrow.triangle.2.circlepath")) \(store.outdatedCount)")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .accessibilityLabel(menuBarAccessibilityLabel)
        }
    }

    private var menuBarAccessibilityLabel: Text {
        if store.outdatedCount == 1 {
            Text("Freshly, 1 update available")
        } else if store.outdatedCount > 1 {
            Text("Freshly, \(store.outdatedCount) updates available")
        } else {
            Text("Freshly")
        }
    }
}
