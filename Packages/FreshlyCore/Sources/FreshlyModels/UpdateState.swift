/// Where an app stands in the update lifecycle.
public enum UpdateState: Sendable, Hashable {
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

/// An error surfaced to the UI. Deliberately a value type with a stable code
/// so states remain `Hashable` and cacheable.
public struct UpdateError: Error, Sendable, Hashable, Codable {
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

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}
