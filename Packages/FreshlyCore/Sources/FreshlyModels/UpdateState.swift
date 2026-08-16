/// Where an app stands in the update lifecycle.
public enum UpdateState: Sendable, Hashable, Codable {
    case checking
    case upToDate
    /// A newer version exists. `best` is the resolver's pick; `alternatives`
    /// are releases the other applicable sources reported, surfaced in the UI
    /// as alternative channels.
    case outdated(best: ReleaseInfo, alternatives: [ReleaseInfo])
    /// The user chose to ignore updates up to and including this version.
    case skipped(untilVersion: AppVersion)
    /// No source knows how to check this app.
    case unsupported
    case failed(UpdateError)
}

/// An error surfaced to the UI. The engine reports *what went wrong* as
/// data; turning that into user-facing text is the app layer's job, so
/// messages localize with the app — including errors that were cached or
/// recorded before the user switched languages.
public struct UpdateError: Error, Sendable, Hashable, Codable {
    /// Coarse classification for programmatic handling (retry policy,
    /// the permission alert). Derived from the reason.
    public enum Code: String, Sendable, Codable {
        case network
        case rateLimited
        case parsing
        case verificationFailed
        case installFailed
        case permissionDenied
        case appRunning
        case cancelled
        case unknown
    }

    /// The specific failure, with whatever context the UI needs to render
    /// an actionable message. `detail` strings carry text from outside the
    /// engine (the OS, a server, a tool) and are shown verbatim.
    public enum Reason: Sendable, Hashable, Codable {
        // Checking a source for updates.
        case sourceRequestFailed(SourceID, detail: String)
        case sourceHTTPStatus(SourceID, status: Int)
        case sourceRateLimited(SourceID)
        case sourceResponseUnreadable(SourceID, detail: String?)

        // Downloading the update artifact.
        case downloadFailed(detail: String)
        case downloadHTTPStatus(status: Int)
        case downloadNotWritable
        case downloadCancelled
        case downloadTooLarge
        case noDirectDownload

        // Unpacking the artifact.
        case packageInstallersUnsupported
        case unsupportedArchive(filename: String)
        case archiveMissingApp
        case diskImageMountFailed
        case diskImageMissingApp

        // Verifying the download and the extracted bundle.
        case signatureMismatch
        case checksumMismatch
        case feedOmittedSignature(appName: String)
        case bundleUnreadable
        case differentApp(bundleID: String)
        case alreadyUpToDate(appName: String)
        case downgradeBlocked
        case codeSignatureInvalid(detail: String)
        case teamChanged(newTeam: String?)
        case gatekeeperRejected

        // Installing the verified bundle.
        case permissionDenied
        case backupPreparationFailed(detail: String)
        case moveAsideFailed(detail: String)
        case moveIntoPlaceFailed(detail: String)
        case rollbackFailed(
            backupPath: String,
            installedPath: String,
            installationDetail: String,
            restoreDetail: String
        )
        case toolNotRunnable(tool: String, detail: String)
        case toolFailed(tool: String, status: Int, detail: String)
        case brewUpgradeFailed(detail: String)

        // The app being updated is in the way.
        case appRunning(appName: String)
        case appDidNotQuit(appName: String)

        // Anything the engine has no better shape for.
        case underlying(detail: String)
    }

    public var reason: Reason

    public var code: Code {
        switch reason {
        case .sourceRequestFailed, .sourceHTTPStatus, .downloadFailed, .downloadHTTPStatus:
            .network
        case .sourceRateLimited:
            .rateLimited
        case .sourceResponseUnreadable:
            .parsing
        case .signatureMismatch, .checksumMismatch, .feedOmittedSignature, .bundleUnreadable,
             .differentApp, .downgradeBlocked, .codeSignatureInvalid, .teamChanged,
             .gatekeeperRejected:
            .verificationFailed
        case .downloadNotWritable, .downloadTooLarge, .noDirectDownload, .alreadyUpToDate,
             .packageInstallersUnsupported, .unsupportedArchive, .archiveMissingApp,
             .diskImageMountFailed, .diskImageMissingApp,
             .backupPreparationFailed, .moveAsideFailed, .moveIntoPlaceFailed, .rollbackFailed,
             .toolNotRunnable, .toolFailed, .brewUpgradeFailed:
            .installFailed
        case .permissionDenied:
            .permissionDenied
        case .appRunning, .appDidNotQuit:
            .appRunning
        case .downloadCancelled:
            .cancelled
        case .underlying:
            .unknown
        }
    }

    public init(_ reason: Reason) {
        self.reason = reason
    }
}
