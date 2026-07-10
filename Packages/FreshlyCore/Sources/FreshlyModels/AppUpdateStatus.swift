import Foundation

/// The unit the UI renders: one installed app plus its current update state.
/// The coordinator streams these as scanning and checking progress.
public struct AppUpdateStatus: Sendable, Hashable, Identifiable {
    public var id: URL { app.id }

    public var app: InstalledApp
    public var state: UpdateState

    public init(app: InstalledApp, state: UpdateState = .checking) {
        self.app = app
        self.state = state
    }

    /// Re-ranks an outdated status so the preferred source's release
    /// becomes the primary one — the user's per-app channel override.
    /// No-op unless that source reported a release that is actually newer
    /// than what is installed.
    public func preferring(_ source: SourceID?) -> AppUpdateStatus {
        guard
            let source,
            case .outdated(let best, let alternatives) = state,
            best.source != source,
            let chosen = alternatives.first(where: { $0.source == source }),
            chosen.isNewer(than: app)
        else {
            return self
        }
        var reranked = self
        var rest = alternatives.filter { $0 != chosen }
        rest.insert(best, at: 0)
        reranked.state = .outdated(best: chosen, alternatives: rest)
        return reranked
    }
}
