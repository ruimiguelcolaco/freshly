import FreshlyModels
import FreshlyScanner

/// Wraps a discoverer and applies a transform to every app it finds —
/// used to enrich scanned apps with catalog definitions before the
/// sources see them.
public struct EnrichingDiscoverer: AppDiscovering, Sendable {
    private let base: any AppDiscovering
    private let transform: @Sendable (InstalledApp) -> InstalledApp

    public init(base: any AppDiscovering, transform: @escaping @Sendable (InstalledApp) -> InstalledApp) {
        self.base = base
        self.transform = transform
    }

    public func apps() -> AsyncStream<InstalledApp> {
        let base = self.base
        let transform = self.transform
        return AsyncStream { continuation in
            let task = Task {
                for await app in base.apps() {
                    continuation.yield(transform(app))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
