import AppKit
import SwiftUI
import FreshlyModels

struct ContentView: View {
    @Environment(AppListStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    /// The low-actionability sections start collapsed so the window opens on
    /// what has an update. Up-to-date, skipped, and no-source apps are all
    /// things the user can't (or chose not to) act on — when everything is
    /// fresh they'd otherwise fill the window and read as the main event.
    @State private var upToDateExpanded = false
    @State private var skippedExpanded = false
    @State private var notCheckableExpanded = false
    @State private var searchText = ""

    var body: some View {
        @Bindable var store = store

        // Snapshot each section once (they recompute on access) and apply the
        // search filter. `signal` drives the list-membership animation.
        let outdated = matching(store.outdated)
        let checking = matching(store.checking)
        let upToDate = matching(store.upToDate)
        let skipped = matching(store.skipped)
        let notCheckable = matching(store.notCheckable)
        let signal = [outdated.count, checking.count, upToDate.count, skipped.count, notCheckable.count]
        let anyExpanded = upToDateExpanded || skippedExpanded || notCheckableExpanded

        List {
            if !outdated.isEmpty {
                Section("Updates Available (\(outdated.count))") {
                    ForEach(outdated) { AppRowView(status: $0) }
                }
            }
            if !checking.isEmpty {
                Section("Checking (\(checking.count))") {
                    ForEach(checking) { AppRowView(status: $0) }
                }
            }
            if !upToDate.isEmpty {
                Section(isExpanded: $upToDateExpanded) {
                    ForEach(upToDate) { AppRowView(status: $0) }
                } header: {
                    CollapsibleHeader("Up to Date (\(upToDate.count))", isExpanded: $upToDateExpanded)
                }
            }
            if !skipped.isEmpty {
                Section(isExpanded: $skippedExpanded) {
                    ForEach(skipped) { AppRowView(status: $0) }
                } header: {
                    CollapsibleHeader("Skipped (\(skipped.count))", isExpanded: $skippedExpanded)
                }
            }
            if !notCheckable.isEmpty {
                Section(isExpanded: $notCheckableExpanded) {
                    ForEach(notCheckable) { AppRowView(status: $0) }
                } header: {
                    CollapsibleHeader("No Update Source (\(notCheckable.count))", isExpanded: $notCheckableExpanded)
                }
            }
        }
        .listStyle(.inset)
        .animation(.snappy(duration: 0.25), value: signal)
        .frame(minWidth: 560, minHeight: 380)
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search apps"))
        .navigationTitle("Freshly")
        .navigationSubtitle(statusSubtitle)
        .toolbar {
            ToolbarItem {
                Button("Update All", systemImage: "arrow.down.circle") {
                    store.updateAll()
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
                // The scan indicator lives where the Refresh action is, rather
                // than as a detached spinner — one control, two states.
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        store.refresh()
                    }
                    .disabled(store.isInstallingAnything)
                    .help("Scan again")
                }
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
            } else if !searchText.isEmpty, outdated.isEmpty, checking.isEmpty,
                      upToDate.isEmpty, skipped.isEmpty, notCheckable.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if searchText.isEmpty, outdated.isEmpty, checking.isEmpty, !anyExpanded {
                allFreshState
                    .allowsHitTesting(false)
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

    /// Filters a section by the search field (app name), no-op when empty.
    private func matching(_ statuses: [AppUpdateStatus]) -> [AppUpdateStatus] {
        guard !searchText.isEmpty else { return statuses }
        return statuses.filter { $0.app.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// The calm state for the most common outcome: nothing to do. Shown when
    /// there are apps but no updates and nothing is expanded.
    private var allFreshState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
            Text("Everything is fresh")
                .font(.title3.weight(.medium))
            if let lastChecked = lastCheckedText {
                Text(lastChecked)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Always-visible window subtitle: what's happening now, or when we last
    /// looked. Builds trust in an app that also checks in the background.
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
}

/// A section header that actually toggles its section. `Section(isExpanded:)`
/// draws no disclosure control in the `.inset` list style, so the built-in
/// collapse is invisible and unclickable — this supplies a chevron + tappable
/// header that drives the binding, matching the native header look.
private struct CollapsibleHeader: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>) {
        self.title = title
        self._isExpanded = isExpanded
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }
}
