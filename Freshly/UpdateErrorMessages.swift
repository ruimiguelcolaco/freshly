import Foundation
import FreshlyModels

extension SourceID {
    /// User-facing source name, shared by rows, menus, and error messages.
    /// `nonisolated`: the app target defaults to MainActor, but localized
    /// string interpolation evaluates in nonisolated autoclosures.
    nonisolated var displayName: String {
        switch self {
        case .sparkle: String(localized: "Sparkle")
        case .macAppStore: String(localized: "Mac App Store")
        case .homebrew: String(localized: "Homebrew")
        case .github: String(localized: "GitHub")
        }
    }
}

extension UpdateError {
    /// The engine reports errors as data; this is where they become words.
    /// Every message says what happened and, when the user can do something
    /// about it, what to do next.
    nonisolated var message: String {
        switch reason {
        case .sourceRequestFailed(let source, let detail):
            String(localized: "Could not check for updates via \(source.displayName): \(detail)")
        case .sourceHTTPStatus(let source, let status):
            String(localized: "Update check failed: \(source.displayName) returned HTTP \(status)")
        case .sourceRateLimited(.github):
            String(localized: "GitHub's rate limit was reached — try again later, or add a GitHub token in Settings")
        case .sourceRateLimited(let source):
            String(localized: "\(source.displayName) is rate-limiting requests — try again later")
        case .sourceResponseUnreadable(let source, .some(let detail)):
            String(localized: "Could not read the reply from \(source.displayName): \(detail)")
        case .sourceResponseUnreadable(let source, nil):
            String(localized: "Could not read the reply from \(source.displayName)")

        case .downloadFailed(let detail):
            String(localized: "Download failed: \(detail)")
        case .downloadHTTPStatus(let status):
            String(localized: "Download failed: the server returned HTTP \(status) — try again later")
        case .downloadNotWritable:
            String(localized: "Could not create the download file — check your free disk space and try again")
        case .downloadCancelled:
            String(localized: "Download cancelled")
        case .noDirectDownload:
            String(localized: "This update has no direct download — open its release page instead")

        case .packageInstallersUnsupported:
            String(localized: "This update ships as an installer package, which Freshly cannot install yet — download and run it manually")
        case .unsupportedArchive(let filename):
            String(localized: "Unsupported update format: \(filename)")
        case .archiveMissingApp:
            String(localized: "The downloaded archive does not contain an app")
        case .diskImageMountFailed:
            String(localized: "Could not open the downloaded disk image")
        case .diskImageMissingApp:
            String(localized: "The downloaded disk image does not contain an app")

        case .signatureMismatch:
            String(localized: "The download's cryptographic signature does not match — refusing to install")
        case .feedOmittedSignature(let appName):
            String(localized: "\(appName) requires signed updates, but its feed provided no signature")
        case .bundleUnreadable:
            String(localized: "The downloaded app could not be read for verification")
        case .differentApp(let bundleID):
            String(localized: "The download is a different app (\(bundleID)) — refusing to install")
        case .alreadyUpToDate(let appName):
            String(localized: "\(appName) is already up to date")
        case .downgradeBlocked:
            String(localized: "The download is not newer than the installed version — downgrade blocked")
        case .codeSignatureInvalid(let detail):
            String(localized: "Code signature validation failed: \(detail)")
        case .teamChanged(.some(let newTeam)):
            String(localized: "The update is signed by a different developer (\(newTeam)) — refusing to install")
        case .teamChanged(nil):
            String(localized: "The update is unsigned, but the installed app has a verified developer — refusing to install")
        case .gatekeeperRejected:
            String(localized: "Gatekeeper rejected the update — it is not signed and notarized")

        case .permissionDenied:
            String(localized: "Freshly needs the App Management permission — enable it in System Settings → Privacy & Security, then try again")
        case .backupPreparationFailed(let detail):
            String(localized: "Could not prepare a backup location: \(detail)")
        case .moveAsideFailed(let detail):
            String(localized: "Could not move the old version aside: \(detail)")
        case .moveIntoPlaceFailed(let detail):
            String(localized: "Could not install the new version: \(detail)")
        case .toolNotRunnable(let tool, let detail):
            String(localized: "Could not run \(tool): \(detail)")
        case .toolFailed(let tool, let status, let detail):
            String(localized: "\(tool) failed (\(status)): \(detail)")
        case .brewUpgradeFailed(let detail):
            String(localized: "brew upgrade failed: \(detail)")

        case .appRunning(let appName):
            String(localized: "\(appName) is running. Quit it to update.")
        case .appDidNotQuit(let appName):
            String(localized: "\(appName) did not quit. Close it and try again.")

        case .underlying(let detail):
            detail
        }
    }
}
