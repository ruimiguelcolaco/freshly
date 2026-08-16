import AppKit
import SwiftUI
import FreshlyModels

struct AppListDetailView: View {
    @Environment(AppListStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let category: AppListCategory

    @State private var searchText = ""

    var body: some View {
        @Bindable var store = store

        let statuses = matching(statuses(for: category))
        let signal = [
            store.outdated.count,
            store.checking.count,
            store.upToDate.count,
            store.skipped.count,
            store.notCheckable.count,
        ]
        let showAllFresh = category == .updates && !store.statuses.isEmpty
            && searchText.isEmpty && statuses.isEmpty

        List(statuses) { status in
            AppRowView(status: status)
        }
        .listStyle(.inset)
        .animation(.snappy(duration: 0.25), value: signal)
        .frame(minWidth: 480, minHeight: 380)
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search apps"))
        .navigationTitle(category.title)
        .navigationSubtitle(statusSubtitle)
        .toolbar {
            ToolbarItem {
                Button("Update All", systemImage: "arrow.down.circle") {
                    _ = store.updateAll()
                }
                    .disabled(store.outdated.isEmpty || store.isInstallingAnything)
                    .help("Download, verify, and install every available update")
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
            } else if !searchText.isEmpty, statuses.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if showAllFresh {
                allFreshState
                    .allowsHitTesting(false)
                    .transition(allFreshTransition)
            } else if statuses.isEmpty {
                categoryEmptyState
            }
        }
        .animation(allFreshAnimation, value: showAllFresh)
        .confirmationDialog(
            quitConfirmationTitle,
            isPresented: $store.isQuitConfirmationPresented
        ) {
            if case .batch? = store.pendingQuitConfirmation {
                Button("Quit & Update All", action: store.confirmQuitAndUpdate)
            } else {
                Button("Quit & Update", action: store.confirmQuitAndUpdate)
            }
            Button("Cancel", role: .cancel, action: store.dismissQuitConfirmation)
        } message: {
            Text(quitConfirmationMessage)
        }
        .alert("App Management Permission Needed", isPresented: $store.showPermissionAlert) {
            Button("Open System Settings", action: openAppManagementSettings)
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("macOS requires your permission before Freshly can update other apps. Enable Freshly under Privacy & Security → App Management, then try again.")
        }
    }

    private var quitConfirmationTitle: String {
        switch store.pendingQuitConfirmation {
        case .single(let status)?:
            String(localized: "\(status.app.name) is running")
        case .batch(_, let running)? where running.count == 1:
            String(localized: "\(running[0].app.name) is running")
        case .batch(_, let running)?:
            String(localized: "\(running.count) apps are running")
        case nil:
            String(localized: "This app is running")
        }
    }

    private var quitConfirmationMessage: String {
        switch store.pendingQuitConfirmation {
        case .single(let status)?:
            return String(localized: "Freshly will quit \(status.app.name) — forcing it if it doesn't respond — then install the update and relaunch it.")
        case .batch(_, let running)?:
            let names = running.map(\.app.name).formatted(.list(type: .and))
            return String(localized: "Freshly will quit \(names) — forcing any that don't respond — then update every app and relaunch those that were running.")
        case nil:
            return ""
        }
    }

    private func statuses(for category: AppListCategory) -> [AppUpdateStatus] {
        switch category {
        case .updates:
            store.outdated + store.checking
        case .all:
            (store.outdated + store.checking + store.upToDate + store.skipped + store.notCheckable)
                .sorted {
                    $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
                }
        case .upToDate:
            store.upToDate
        case .skipped:
            store.skipped
        case .notCheckable:
            store.notCheckable
        }
    }

    private func matching(_ statuses: [AppUpdateStatus]) -> [AppUpdateStatus] {
        guard !searchText.isEmpty else { return statuses }
        return statuses.filter { $0.app.name.localizedStandardContains(searchText) }
    }

    private var allFreshState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text("Everything is fresh")
                .font(.title3.weight(.medium))
            if let lastCheckedText {
                Text(lastCheckedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryEmptyState: some View {
        ContentUnavailableView {
            Label(categoryEmptyTitle, systemImage: category.systemImage)
        } description: {
            Text(categoryEmptyDescription)
        }
    }

    private var categoryEmptyTitle: LocalizedStringKey {
        switch category {
        case .updates: "Everything is fresh"
        case .all: "No Applications Found"
        case .upToDate: "No Up-to-Date Applications"
        case .skipped: "No Skipped Updates"
        case .notCheckable: "Every Application Has an Update Source"
        }
    }

    private var categoryEmptyDescription: LocalizedStringKey {
        switch category {
        case .updates: "No updates are currently available."
        case .all: "Nothing was found in /Applications or ~/Applications."
        case .upToDate: "Applications will appear here after Freshly confirms their latest version."
        case .skipped: "Updates you choose to skip will appear here."
        case .notCheckable: "Freshly can check every discovered application."
        }
    }

    private var statusSubtitle: Text {
        if store.isScanning {
            return Text("Checking for updates…")
        }
        if store.outdated.count == 1 {
            return Text("1 update available")
        }
        if store.outdated.count > 1 {
            return Text("\(store.outdated.count) updates available")
        }
        return lastCheckedText.map(Text.init) ?? Text(verbatim: "")
    }

    private var lastCheckedText: String? {
        guard let date = store.lastCheckedAt else { return nil }
        let relative = date.formatted(.relative(presentation: .named))
        return String(localized: "Last checked \(relative)")
    }

    private var allFreshAnimation: Animation {
        .snappy(duration: reduceMotion ? 0.15 : 0.25)
    }

    private var allFreshTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    private func openAppManagementSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
