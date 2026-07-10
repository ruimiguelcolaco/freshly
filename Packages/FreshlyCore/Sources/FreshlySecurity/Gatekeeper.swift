import Foundation

/// Gatekeeper policy assessment. A protocol so the install pipeline can be
/// tested without the real system policy daemon.
public protocol GatekeeperAssessing: Sendable {
    /// Whether the system's execution policy accepts the bundle.
    func assess(appAt url: URL) async throws -> Bool
}

/// Assesses through `spctl`, the system policy tool. Acceptance requires a
/// Developer ID signature and (on current systems) notarization.
public struct SpctlGatekeeper: GatekeeperAssessing {
    public init() {}

    public func assess(appAt url: URL) async throws -> Bool {
        let output = try await Subprocess.run(
            "/usr/sbin/spctl",
            ["--assess", "--type", "execute", url.path]
        )
        return output.status == 0
    }
}
