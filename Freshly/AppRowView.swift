import AppKit
import SwiftUI
import FreshlyModels

struct AppRowView: View {
    @Environment(AppListStore.self) private var store

    let status: AppUpdateStatus

    @State private var isHovering = false

    private var release: ReleaseInfo? {
        if case .outdated(let best, _) = status.state { return best }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: status.app.path.path))
                .resizable()
                .frame(width: 32, height: 32)
                .help(signatureHelp)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(status.app.name)
                        .fontWeight(.medium)
                        .help(status.app.bundleID)
                    signatureBadge
                }
                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let phase = store.installing[status.id] {
                installProgress(phase)
            } else {
                trailingContent
                overflowMenu
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
    }

    /// A hover-revealed `•••` menu duplicating the context menu, so the row's
    /// actions are discoverable without a right-click. Always in the tree (so
    /// an open menu isn't torn down when the pointer leaves the row) but only
    /// shown and clickable on hover; space is reserved so revealing it never
    /// shifts the trailing content.
    private var overflowMenu: some View {
        Menu {
            contextMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 20)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .accessibilityLabel("More actions")
    }

    @ViewBuilder
    private func installProgress(_ phase: InstallPhase) -> some View {
        Text(phaseLabel(phase))
            .font(.caption)
            .foregroundStyle(.secondary)
        if case .downloading(.some(let fraction)) = phase {
            HStack(spacing: 6) {
                ProgressView(value: fraction)
                    .frame(width: 72)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func phaseLabel(_ phase: InstallPhase) -> String {
        switch phase {
        case .waiting: String(localized: "Waiting…")
        case .downloading: String(localized: "Downloading…")
        case .verifyingDownload: String(localized: "Verifying…")
        case .extracting: String(localized: "Extracting…")
        case .validating: String(localized: "Validating…")
        case .installing: String(localized: "Installing…")
        case .relaunching: String(localized: "Relaunching…")
        case .finished: String(localized: "Done")
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch status.state {
        case .checking:
            installedVersionText
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            installedVersionText
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .help("Up to date")
                .accessibilityLabel("Up to date")
        case .outdated(let best, _):
            if let error = store.installErrors[status.id] {
                ErrorBadge(error: error)
            }
            if best.changelog != nil || best.embeddedNotesURL != nil || best.releaseNotesURL != nil {
                ReleaseNotesButton(status: status, release: best) {
                    versionTransition(best)
                }
            } else {
                versionTransition(best)
            }
            Button(updateButtonTitle(for: best)) {
                store.requestUpdate(for: status)
            }
            .buttonStyle(.bordered)
            .help(updateButtonHelp(for: best))
        case .skipped(let untilVersion):
            installedVersionText
            Text("Skipped \(untilVersion.rawValue)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .unsupported:
            // The "No Update Source" section header already says this — the
            // bare version keeps the row from looking empty without repeating.
            installedVersionText
        case .failed(let error):
            installedVersionText
            ErrorBadge(error: error)
        }
    }

    private var installedVersionText: some View {
        Text(status.app.version.rawValue)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// The "installed → available" versions. Doubles as the release-notes
    /// trigger (see the outdated case) so "what's new" is one obvious tap on
    /// the update itself, not a stray icon.
    private func versionTransition(_ best: ReleaseInfo) -> some View {
        Text("\(status.app.version.rawValue) → \(best.version.rawValue)")
            .foregroundStyle(.orange)
            .fontWeight(.medium)
            .monospacedDigit()
            .accessibilityLabel(Text("Update available from \(status.app.version.rawValue) to \(best.version.rawValue)"))
    }

    /// Only draws for trust states worth flagging — an ad-hoc or unsigned
    /// app. Notarized/signed apps (the overwhelming majority) render nothing,
    /// so the rare unsigned one stands out instead of drowning in green seals.
    @ViewBuilder
    private var signatureBadge: some View {
        switch status.app.signature.status {
        case .adHocSigned:
            Image(systemName: "seal")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Ad hoc signature — no verified developer")
                .accessibilityLabel("Ad hoc signature — no verified developer")
        case .unsigned:
            Image(systemName: "xmark.seal")
                .font(.caption)
                .foregroundStyle(.red)
                .help("Not code-signed")
                .accessibilityLabel("Not code-signed")
        case .notarized, .signed, .unknown:
            EmptyView()
        }
    }

    /// The signing story, surfaced on hover of the app icon so it stays
    /// reachable now that the clean-signature badge is gone.
    private var signatureHelp: String {
        switch status.app.signature.status {
        case .notarized, .signed:
            let identity = status.app.signature.signingIdentity
                ?? String(localized: "Signed by a verified developer")
            if let team = status.app.signature.teamID {
                return "\(identity) (\(team))"
            }
            return identity
        case .adHocSigned:
            return String(localized: "Ad hoc signature — no verified developer")
        case .unsigned:
            return String(localized: "Not code-signed")
        case .unknown:
            return String(localized: "Signature not verified")
        }
    }

    /// Secondary line under the name. Repurposed from the bundle ID (now on
    /// hover of the name) to the update's provenance — where it comes from
    /// and, when known, how recently it shipped. Only outdated rows carry it;
    /// everything else stays a single, calmer line.
    private var secondaryLine: String? {
        guard case .outdated(let best, _) = status.state else { return nil }
        let via = String(localized: "via \(best.source.displayName)")
        guard let publishedAt = best.publishedAt else { return via }
        return "\(via) · \(publishedAt.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Open \(status.app.name)") {
            NSWorkspace.shared.open(status.app.path)
        }
        if let notes = release?.releaseNotesURL {
            Button("Release Notes…") { NSWorkspace.shared.open(notes) }
        }
        if let download = release?.downloadURL {
            Button("Download Update in Browser…") { NSWorkspace.shared.open(download) }
        }
        if case .outdated(let best, let alternatives) = status.state, store.installing[status.id] == nil {
            if !alternatives.isEmpty {
                Divider()
                Menu("Update Via") {
                    ForEach([best] + alternatives, id: \.source) { candidate in
                        Button {
                            store.setPreferredSource(candidate.source, for: status)
                        } label: {
                            if candidate.source == best.source {
                                Label(candidate.source.displayName, systemImage: "checkmark")
                            } else {
                                Text("\(candidate.source.displayName) (\(candidate.version.rawValue))")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Skip This Version") { store.skipVersion(for: status) }
        }
        if case .skipped = status.state {
            Divider()
            Button("Stop Skipping This Version") { store.stopSkipping(status) }
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([status.app.path])
        }
    }

    private func updateButtonTitle(for release: ReleaseInfo) -> String {
        if release.source == .macAppStore, release.downloadURL == nil {
            return String(localized: "App Store…")
        }
        if release.downloadURL == nil {
            return String(localized: "View Release…")
        }
        return store.installErrors[status.id] == nil
            ? String(localized: "Update")
            : String(localized: "Try Again")
    }

    private func updateButtonHelp(for release: ReleaseInfo) -> String {
        if release.source == .macAppStore, release.downloadURL == nil {
            return String(localized: "Update in the App Store — macOS no longer lets other apps install App Store updates")
        }
        if release.downloadURL == nil {
            return String(localized: "This update has no direct download — opens its release page")
        }
        return String(localized: "Download, verify, and install version \(release.version.rawValue)")
    }
}
