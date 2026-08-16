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
    /// One bound shared by every source request in the scan.
    private let maxConcurrentRequests: Int

    public init(
        discoverer: any AppDiscovering,
        registry: SourceRegistry,
        maxConcurrentRequests: Int = 10
    ) {
        self.discoverer = discoverer
        self.registry = registry
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
    }

    public func checkAll() -> AsyncStream<AppUpdateStatus> {
        let discoverer = self.discoverer
        let registry = self.registry
        let width = maxConcurrentRequests
        let limiter = RequestLimiter(limit: width)

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
                            await Self.check(app, against: registry, limiter: limiter)
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
        await check(
            app,
            against: registry,
            limiter: RequestLimiter(limit: max(1, registry.sources.count))
        )
    }

    private static func check(
        _ app: InstalledApp,
        against registry: SourceRegistry,
        limiter: RequestLimiter
    ) async -> AppUpdateStatus {
        let applicable = registry.applicableSources(for: app)
        guard !applicable.isEmpty else {
            return AppUpdateStatus(app: app, state: .unsupported)
        }

        let answers = await withTaskGroup(
            of: (Int, SourceAnswer).self,
            returning: [SourceAnswer].self
        ) { group in
            for (index, entry) in applicable.enumerated() {
                group.addTask {
                    let answer = await limiter.run {
                        do {
                            return SourceAnswer.release(
                                try await entry.source.latestRelease(for: app)
                            )
                        } catch let error as UpdateError {
                            return SourceAnswer.failure(error)
                        } catch {
                            return SourceAnswer.failure(
                                UpdateError(.underlying(detail: error.localizedDescription))
                            )
                        }
                    }
                    return (index, answer)
                }
            }
            var ordered = Array<SourceAnswer?>(repeating: nil, count: applicable.count)
            for await (index, answer) in group {
                ordered[index] = answer
            }
            return ordered.compactMap { $0 }
        }

        var candidates: [ReleaseInfo] = []
        var failures: [UpdateError] = []
        for answer in answers {
            switch answer {
            case .release(let release):
                if let release { candidates.append(release) }
            case .failure(let error):
                failures.append(error)
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

private enum SourceAnswer: Sendable {
    case release(ReleaseInfo?)
    case failure(UpdateError)
}

/// A FIFO permit pool shared across every app and source in one scan.
private actor RequestLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func run<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        defer { release() }
        return await operation()
    }

    private func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
