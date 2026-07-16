import AppKit
import SwiftUI
import FreshlyModels

struct ContentView: View {
    @Environment(AppListStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store

        List {
            if !store.outdated.isEmpty {
                Section("Updates Available (\(store.outdated.count))") {
                    ForEach(store.outdated) { AppRowView(status: $0) }
                }
            }
            if !store.checking.isEmpty {
                Section("Checking (\(store.checking.count))") {
                    ForEach(store.checking) { AppRowView(status: $0) }
                }
            }
            if !store.upToDate.isEmpty {
                Section("Up to Date (\(store.upToDate.count))") {
                    ForEach(store.upToDate) { AppRowView(status: $0) }
                }
            }
            if !store.skipped.isEmpty {
                Section("Skipped (\(store.skipped.count))") {
                    ForEach(store.skipped) { AppRowView(status: $0) }
                }
            }
            if !store.notCheckable.isEmpty {
                Section("No Update Source (\(store.notCheckable.count))") {
                    ForEach(store.notCheckable) { AppRowView(status: $0) }
                }
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 560, minHeight: 380)
        .navigationTitle("Freshly")
        .toolbar {
            ToolbarItem {
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ToolbarItem {
                if store.outdated.count > 1 {
                    Button("Update All (\(store.outdated.count))") {
                        store.updateAll()
                    }
                    .disabled(store.isInstallingAnything)
                    .help("Download, verify, and install every available update")
                }
            }
            ToolbarItem {
                Button("Update History", systemImage: "clock.arrow.circlepath") {
                    openWindow(id: "history")
                }
                .help("Show the updates installed through Freshly")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    store.refresh()
                }
                .disabled(store.isScanning || store.isInstallingAnything)
                .help("Scan again")
            }
        }
        .overlay {
            if store.statuses.isEmpty {
                if store.isScanning {
                    ProgressView("Scanning applications…")
                } else {
                    ContentUnavailableView(
                        "No Applications Found",
                        systemImage: "app.dashed",
                        description: Text("Nothing was found in /Applications or ~/Applications.")
                    )
                }
            }
        }
        .confirmationDialog(
            "\(store.pendingQuitConfirmation?.app.name ?? String(localized: "This app")) is running",
            isPresented: Binding(
                get: { store.pendingQuitConfirmation != nil },
                set: { if !$0 { store.dismissQuitConfirmation() } }
            )
        ) {
            Button("Quit & Update") { store.confirmQuitAndUpdate() }
            Button("Cancel", role: .cancel) { store.dismissQuitConfirmation() }
        } message: {
            Text("Freshly will quit \(store.pendingQuitConfirmation?.app.name ?? String(localized: "the app")) — forcing it if it doesn't respond — then install the update and relaunch it.")
        }
        .alert("App Management Permission Needed", isPresented: $store.showPermissionAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("macOS requires your permission before Freshly can update other apps. Enable Freshly under Privacy & Security → App Management, then try again.")
        }
    }
}
