import AppKit
import SwiftUI
import FreshlyModels

struct MenuBarView: View {
    @Environment(AppListStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.isScanning {
                Text("Checking for updates…")
            } else if store.outdatedCount == 0 {
                Text("Everything is fresh")
            } else if store.outdatedCount == 1 {
                Text("1 update available")
            } else {
                Text("\(store.outdatedCount) updates available")
            }
        }

        if !store.outdated.isEmpty {
            Divider()
            if store.outdated.count > 1 {
                Button("Update All (\(store.outdated.count))") { store.updateAll() }
                    .disabled(store.isInstallingAnything)
            }
            ForEach(store.outdated.prefix(12)) { status in
                Menu("\(status.app.name)  \(versionTransition(status))") {
                    Button("Update") {
                        openMainWindow()
                        store.requestUpdate(for: status)
                    }
                    .disabled(store.installing[status.id] != nil)
                    Button("Show in Freshly") { openMainWindow() }
                }
            }
        }

        Divider()
        Button("Open Freshly") { openMainWindow() }
        Button("Check Again") { store.refresh() }
            .disabled(store.isScanning)
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit Freshly") {
            // The one quit that is not intercepted — see FreshlyAppDelegate.
            FreshlyAppDelegate.quitRequested = true
            NSApplication.shared.terminate(nil)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func versionTransition(_ status: AppUpdateStatus) -> String {
        guard case .outdated(let best, _) = status.state else { return "" }
        return AppVersion.transition(from: status.app.version, to: best.version)
    }
}
