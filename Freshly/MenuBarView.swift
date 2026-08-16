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

        if let nextCheckText {
            Text(nextCheckText)
        }

        if !store.outdated.isEmpty {
            Divider()
            if store.outdated.count > 1 {
                Button("Update All (\(store.outdated.count))") {
                    if store.updateAll() == .requiresQuitConfirmation {
                        openMainWindow()
                    }
                }
                    .disabled(store.isInstallingAnything)
            }
            ForEach(store.outdated.prefix(12)) { status in
                Menu("\(status.app.name)  \(versionTransition(status))") {
                    Button("Update") { update(status) }
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
        // Force focus so the window fronts even when Freshly is behind another
        // app (its menu-bar/accessory state won't come forward on its own).
        NSApp.activate(ignoringOtherApps: true)
    }

    private func update(_ status: AppUpdateStatus) {
        if store.requestUpdate(for: status) == .requiresQuitConfirmation {
            openMainWindow()
        }
    }

    private func versionTransition(_ status: AppUpdateStatus) -> String {
        guard case .outdated(let best, _) = status.state else { return "" }
        return AppVersion.transition(from: status.app.version, to: best.version)
    }

    private var nextCheckText: String? {
        guard !store.isScanning, let date = store.nextAutomaticCheckAt else { return nil }
        let relative = date.formatted(.relative(presentation: .named))
        if store.isAutomaticRetryPending {
            return String(localized: "Retry scheduled \(relative)")
        }
        return String(localized: "Next check \(relative)")
    }
}
