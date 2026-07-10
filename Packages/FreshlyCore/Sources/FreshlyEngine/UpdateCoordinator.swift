import Foundation
import FreshlyModels
import FreshlyScanner
import FreshlySources

/// Orchestrates a full run: discover installed apps, fan out version checks
/// across the applicable sources, and stream `AppUpdateStatus` values to
/// the UI as they resolve.
///
/// Each app produces two emissions: `.checking` the moment it is discovered
/// (so the UI can render it immediately) and its final state once the
/// sources answered.
public struct UpdateCoordinator: Sendable {
    private let discoverer: any AppDiscovering
    private let registry: SourceRegistry
    /// Bound on concurrent network checks across apps.
    private let maxConcurrentChecks: Int

    public init(
        discoverer: any AppDiscovering,
        registry: SourceRegistry,
        maxConcurrentChecks: Int = 10
    ) {
        self.discoverer = discoverer
        self.registry = registry
        self.maxConcurrentChecks = max(1, maxConcurrentChecks)
    }

    public func checkAll() -> AsyncStream<AppUpdateStatus> {
        let discoverer = self.discoverer
        let registry = self.registry
        let width = maxConcurrentChecks

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: AppUpdateStatus.self) { group in
                    var running = 0
                    for await app in discoverer.apps() {
                        if Task.isCancelled { break }
                        continuation.yield(AppUpdateStatus(app: app, state: .checking))

                        if running >= width, let finished = await group.next() {
                            running -= 1
                            continuation.yield(finished)
                        }
                        group.addTask {
                            await Self.check(app, against: registry)
                        }
                        running += 1
                    }
                    for await finished in group {
                        continuation.yield(finished)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Queries the applicable sources for one app, strongest claim first,
    /// and resolves the answers into a final state.
    static func check(_ app: InstalledApp, against registry: SourceRegistry) async -> AppUpdateStatus {
        let applicable = registry.applicableSources(for: app)
        guard !applicable.isEmpty else {
            return AppUpdateStatus(app: app, state: .unsupported)
        }

        var candidates: [ReleaseInfo] = []
        var failures: [UpdateError] = []
        for (source, _) in applicable {
            do {
                if let release = try await source.latestRelease(for: app) {
                    candidates.append(release)
                }
            } catch let error as UpdateError {
                failures.append(error)
            } catch {
                failures.append(UpdateError(code: .unknown, message: error.localizedDescription))
            }
        }

        return AppUpdateStatus(app: app, state: resolve(app: app, candidates: candidates, failures: failures))
    }

    /// The channel the app was installed through wins: `applicableSources`
    /// already orders authoritative sources first and queries preserve that
    /// order, so the first candidate is the resolver's pick. Everything else
    /// is surfaced as alternative channels.
    static func resolve(
        app: InstalledApp,
        candidates: [ReleaseInfo],
        failures: [UpdateError]
    ) -> UpdateState {
        guard let best = candidates.first else {
            if let failure = failures.first {
                return .failed(failure)
            }
            return .unsupported
        }
        if best.isNewer(than: app) {
            return .outdated(best: best, alternatives: Array(candidates.dropFirst()))
        }
        return .upToDate
    }
}
