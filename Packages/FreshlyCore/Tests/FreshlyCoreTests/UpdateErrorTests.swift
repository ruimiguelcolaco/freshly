import Foundation
import Testing
import FreshlyModels

@Suite("UpdateError")
struct UpdateErrorTests {
    @Test("Codes derive from reasons")
    func codeDerivation() {
        #expect(UpdateError(.sourceRequestFailed(.sparkle, detail: "x")).code == .network)
        #expect(UpdateError(.sourceHTTPStatus(.github, status: 500)).code == .network)
        #expect(UpdateError(.sourceRateLimited(.github)).code == .rateLimited)
        #expect(UpdateError(.sourceResponseUnreadable(.homebrew, detail: nil)).code == .parsing)
        #expect(UpdateError(.downloadCancelled).code == .cancelled)
        #expect(UpdateError(.signatureMismatch).code == .verificationFailed)
        #expect(UpdateError(.teamChanged(newTeam: nil)).code == .verificationFailed)
        #expect(UpdateError(.gatekeeperRejected).code == .verificationFailed)
        #expect(UpdateError(.permissionDenied).code == .permissionDenied)
        #expect(UpdateError(.appRunning(appName: "X")).code == .appRunning)
        #expect(UpdateError(.brewUpgradeFailed(detail: "x")).code == .installFailed)
        #expect(UpdateError(.rollbackFailed(
            backupPath: "/tmp/Fixture.app",
            installedPath: "/Applications/Fixture.app",
            installationDetail: "install",
            restoreDetail: "restore"
        )).code == .installFailed)
        #expect(UpdateError(.underlying(detail: "x")).code == .unknown)
    }

    @Test("Reasons survive a Codable roundtrip — the scan cache depends on it")
    func codableRoundtrip() throws {
        let errors: [UpdateError] = [
            UpdateError(.sourceRequestFailed(.macAppStore, detail: "offline")),
            UpdateError(.sourceResponseUnreadable(.sparkle, detail: nil)),
            UpdateError(.toolFailed(tool: "brew", status: 1, detail: "boom")),
            UpdateError(.teamChanged(newTeam: nil)),
            UpdateError(.permissionDenied),
            UpdateError(.rollbackFailed(
                backupPath: "/tmp/Fixture.app",
                installedPath: "/Applications/Fixture.app",
                installationDetail: "install",
                restoreDetail: "restore"
            )),
        ]
        let data = try JSONEncoder().encode(errors)
        let decoded = try JSONDecoder().decode([UpdateError].self, from: data)
        #expect(decoded == errors)
    }
}
