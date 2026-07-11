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

    public func upgradeCask(_ token: String) async throws {
        do {
            try await Subprocess.runChecked(
                executable.path,
                ["upgrade", "--cask", token],
                environment: [
                    "HOMEBREW_NO_AUTO_UPDATE": "1",
                    "HOMEBREW_NO_ENV_HINTS": "1",
                    "HOMEBREW_NO_INSTALL_CLEANUP": "1",
                    "NONINTERACTIVE": "1",
                ]
            )
        } catch let error as UpdateError {
            if case .toolFailed(_, _, let detail) = error.reason {
                throw UpdateError(.brewUpgradeFailed(detail: detail))
            }
            throw error
        }
    }
}
