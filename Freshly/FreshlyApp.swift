import SwiftUI
import Sparkle

@main
struct FreshlyApp: App {
    @NSApplicationDelegateAdaptor(FreshlyAppDelegate.self) private var appDelegate
    @State private var store: AppListStore
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppRuntime.isTesting,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let store = AppListStore()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        // A single, reusable main window. `Window` (not `WindowGroup`) so
        // reopening from the menu bar fronts the existing window instead of
        // spawning a new one each time — and there is no stray ⌘N.
        Window("Freshly", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 720, height: 480)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Freshly Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
        }

        Window("Update History", id: "history") {
            HistoryView()
                .environment(store)
        }
        .defaultSize(width: 560, height: 400)

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            MenuBarLabel(count: store.outdatedCount)
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
