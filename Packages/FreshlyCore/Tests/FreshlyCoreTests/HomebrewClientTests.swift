import Foundation
import Testing
import FreshlyModels
@testable import FreshlyInstaller

@Suite("HomebrewClient")
struct HomebrewClientTests {
    @Test("Recognizes Homebrew's user-facing upgrade phases")
    func parsesUpgradePhases() {
        #expect(HomebrewClient.installPhase(for: "==> Fetching downloads for: docker") == .preparing)
        #expect(HomebrewClient.installPhase(for: "==> Downloading https://example.com/app.dmg") == .downloading(fraction: nil))
        #expect(HomebrewClient.installPhase(for: "==> Installing Cask docker") == .installing)
        #expect(HomebrewClient.installPhase(for: "==> Purging files for version 1.0") == .finalizing)
        #expect(HomebrewClient.installPhase(for: "Unrelated output") == nil)
    }

    @Test("Streams phases while a cask upgrade runs")
    func streamsUpgradePhases() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-homebrew-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "brew-fixture")
        try """
        #!/bin/sh
        echo '==> Downloading https://example.com/app.dmg'
        echo '==> Installing Cask example'
        echo '==> Purging files for version 1.0'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let recorder = PhaseRecorder()
        try await HomebrewClient(executable: executable).upgradeCask("example") { phase in
            await recorder.append(phase)
        }

        let phases = await recorder.phases
        #expect(phases.first == .preparing)
        #expect(phases.contains(.downloading(fraction: nil)))
        #expect(phases.contains(.installing))
        #expect(phases.last == .finalizing)
    }

    @Test("Preserves streamed output when brew fails")
    func reportsUpgradeFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-homebrew-failure-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "brew-fixture")
        try """
        #!/bin/sh
        echo 'Cask upgrade failed' >&2
        exit 7
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        do {
            try await HomebrewClient(executable: executable).upgradeCask("example")
            Issue.record("Expected the Homebrew upgrade to fail")
        } catch let error as UpdateError {
            guard case .brewUpgradeFailed(let detail) = error.reason else {
                Issue.record("Expected a brew-upgrade error, got \(error.reason)")
                return
            }
            #expect(detail == "Cask upgrade failed")
        }
    }
}

private actor PhaseRecorder {
    private(set) var phases: [InstallPhase] = []

    func append(_ phase: InstallPhase) {
        phases.append(phase)
    }
}
