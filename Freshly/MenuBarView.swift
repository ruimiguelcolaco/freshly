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
            ForEach(store.outdated.prefix(12)) { status in
                Button {
                    openMainWindow()
                } label: {
                    Text("\(status.app.name)  \(versionTransition(status))")
                }
            }
        }

        Divider()
        Button("Open Freshly") { openMainWindow() }
        Button("Check Again") { store.refresh() }
            .disabled(store.isScanning)
        Divider()
        Button("Quit Freshly") { NSApplication.shared.terminate(nil) }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func versionTransition(_ status: AppUpdateStatus) -> String {
        guard case .outdated(let best, _) = status.state else { return "" }
        return "\(status.app.version.rawValue) → \(best.version.rawValue)"
    }
}
