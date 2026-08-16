import Foundation
import FreshlyModels
import FreshlySecurity

/// Runs the locally installed brew for apps that were installed as casks —
/// upgrading through brew keeps its bookkeeping (Caskroom versions, `brew
/// outdated`) consistent, which a direct in-place swap would break.
public struct HomebrewClient: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public static func detect() -> HomebrewClient? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { HomebrewClient(executable: URL(fileURLWithPath: $0)) }
    }

    public func upgradeCask(
        _ token: String,
        progress: @escaping @Sendable (InstallPhase) async -> Void = { _ in }
    ) async throws {
        do {
            await progress(.preparing)
            try await Subprocess.runStreamingChecked(
                executable.path,
                ["upgrade", "--cask", token],
                environment: [
                    "HOMEBREW_NO_AUTO_UPDATE": "1",
                    "HOMEBREW_NO_ENV_HINTS": "1",
                    "HOMEBREW_NO_INSTALL_CLEANUP": "1",
                    "NONINTERACTIVE": "1",
                ],
                onOutput: { line in
                    if let phase = Self.installPhase(for: line) {
                        await progress(phase)
                    }
                }
            )
            await progress(.finalizing)
        } catch let error as UpdateError {
            if case .toolFailed(_, _, let detail) = error.reason {
                throw UpdateError(.brewUpgradeFailed(detail: detail))
            }
            throw error
        }
    }

    static func installPhase(for outputLine: String) -> InstallPhase? {
        if outputLine.contains("Downloading") || outputLine.contains("Already downloaded") {
            return .downloading(fraction: nil)
        }
        if outputLine.contains("Installing Cask")
            || outputLine.contains("Moving App")
            || outputLine.contains("Linking Binary") {
            return .installing
        }
        if outputLine.contains("Purging files")
            || outputLine.contains("successfully upgraded")
            || outputLine.contains("🍺") {
            return .finalizing
        }
        if outputLine.contains("Fetching downloads") || outputLine.contains("Upgrading") {
            return .preparing
        }
        return nil
    }
}
