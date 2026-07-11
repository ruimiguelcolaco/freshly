import Foundation

/// The unit the UI renders: one installed app plus its current update state.
/// The coordinator streams these as scanning and checking progress.
public struct AppUpdateStatus: Sendable, Hashable, Codable, Identifiable {
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

    /// Statuses that became outdated relative to a previous snapshot: an
    /// app counts when it is outdated now and was not already outdated to
    /// the same version before — a newly discovered app, or a newer
    /// version appearing. Drives "new updates" notifications.
    public static func newlyOutdated(
        in current: some Collection<AppUpdateStatus>,
        comparedTo previous: some Collection<AppUpdateStatus>
    ) -> [AppUpdateStatus] {
        var previousBest: [String: AppVersion] = [:]
        for status in previous {
            if case .outdated(let best, _) = status.state {
                previousBest[status.app.bundleID] = best.version
            }
        }
        return current.filter { status in
            guard case .outdated(let best, _) = status.state else { return false }
            return previousBest[status.app.bundleID] != best.version
        }
    }
}
