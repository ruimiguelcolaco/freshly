import FreshlyModels

/// How strongly a source claims responsibility for an app. Determined
/// offline (no network) from what the scanner found on disk.
public enum SourceApplicability: Sendable, Comparable {
    case notApplicable
    /// The source can report a version but is not the app's install channel
    /// (e.g. a Homebrew cask exists for an app installed manually).
    case candidate
    /// This is the channel the app is installed or updated through
    /// (Mac App Store receipt present, Sparkle feed declared, …).
    case authoritative
}

/// One place Freshly can learn about newer versions: Sparkle appcasts, the
/// Mac App Store, Homebrew casks, GitHub Releases, and whatever the
/// community adds next. See `docs/ADDING_A_SOURCE.md`.
public protocol UpdateSource: Sendable {
    var id: SourceID { get }

    /// Cheap, offline: does this source apply to the given app at all?
    func applicability(for app: InstalledApp) -> SourceApplicability

    /// Queries the source for the latest release. May hit the network;
    /// implementations are expected to cache and to use conditional requests
    /// where the backing service supports them.
    func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo?
}
