import FreshlyInstaller
import FreshlyModels

/// Narrow installer seam used by the app coordinator. Production delegates
/// to `UpdateInstaller`; tests can observe dispatch without touching bundles.
protocol UpdateInstalling: Sendable {
    func install(
        _ release: ReleaseInfo,
        over app: InstalledApp,
        quitIfRunning: Bool
    ) -> AsyncThrowingStream<InstallPhase, Error>
}

extension UpdateInstaller: UpdateInstalling {}
