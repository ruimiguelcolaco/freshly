import CryptoKit
import Foundation
import Testing
import FreshlyModels
import FreshlySecurity
@testable import FreshlyInstaller

private struct StubGatekeeper: GatekeeperAssessing {
    let accepts: Bool
    func assess(appAt url: URL) async throws -> Bool { accepts }
}

/// End-to-end pipeline tests against real ad-hoc-signed bundles, real zip
/// archives served over `file://`, and real EdDSA keys — only Gatekeeper is
/// stubbed (ad-hoc test bundles can never pass the real policy).
@Suite("UpdateInstaller", .serialized)
struct UpdateInstallerTests {
    private struct Scenario {
        let workDir: URL
        let installedBundle: URL
        let installed: InstalledApp
        let release: ReleaseInfo
    }

    /// Builds: an "installed" v1.0 app, a v2.0 update zipped next to it,
    /// and a release pointing at the zip via `file://`.
    private func makeScenario(
        newBundleID: String = "com.freshly.Fixture",
        newVersion: String = "2.0",
        newBuild: String = "200",
        signArtifact: Bool = true,
        pinEdDSAKey: Bool = true,
        tamper: Bool = false,
        releaseSource: SourceID = .sparkle,
        artifactName: String? = nil
    ) throws -> Scenario {
        let workDir = try FixtureApps.makeWorkDirectory()

        let key = Curve25519.Signing.PrivateKey()
        let applications = workDir.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let installedBundle = try FixtureApps.makeSignedApp(
            named: "Fixture",
            in: applications,
            bundleID: "com.freshly.Fixture",
            version: "1.0",
            build: "100",
            edPublicKey: pinEdDSAKey ? key.publicKey.rawRepresentation.base64EncodedString() : nil
        )

        let staging = workDir.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let newBundle = try FixtureApps.makeSignedApp(
            named: "Fixture",
            in: staging,
            bundleID: newBundleID,
            version: newVersion,
            build: newBuild
        )
        var archive = try FixtureApps.zip(newBundle)
        if let artifactName {
            let renamed = archive.deletingLastPathComponent().appending(path: artifactName)
            try FileManager.default.moveItem(at: archive, to: renamed)
            archive = renamed
        }

        if tamper {
            var data = try Data(contentsOf: archive)
            data[data.count / 2] ^= 0xFF
            try data.write(to: archive)
        }

        let signature = signArtifact
            ? try key.signature(for: Data(contentsOf: archive)).base64EncodedString()
            : nil
        let release = ReleaseInfo(
            version: AppVersion(newVersion),
            build: newBuild,
            edSignature: signature,
            source: releaseSource,
            downloadURL: archive
        )
        return Scenario(
            workDir: workDir,
            installedBundle: installedBundle,
            installed: try FixtureApps.installedApp(for: installedBundle),
            release: release
        )
    }

    private func runInstall(
        _ scenario: Scenario,
        gatekeeperAccepts: Bool = false
    ) async throws -> [InstallPhase] {
        let installer = UpdateInstaller(gatekeeper: StubGatekeeper(accepts: gatekeeperAccepts))
        var phases: [InstallPhase] = []
        for try await phase in installer.install(scenario.release, over: scenario.installed) {
            phases.append(phase)
        }
        return phases
    }

    private func installedVersion(_ scenario: Scenario) -> String? {
        let plist = scenario.installedBundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    @Test("Full pipeline: EdDSA-verified update installs and reports every phase")
    func successfulInstall() async throws {
        let scenario = try makeScenario()
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        // Gatekeeper is told to reject to prove the EdDSA-verified path
        // legitimately does not consult it (Sparkle's trust model).
        let phases = try await runInstall(scenario, gatekeeperAccepts: false)

        #expect(phases.contains(.verifyingDownload))
        #expect(phases.contains(.extracting))
        #expect(phases.contains(.validating))
        #expect(phases.contains(.installing))
        #expect(phases.last == .finished)
        #expect(installedVersion(scenario) == "2.0")
    }

    @Test("A tampered artifact fails EdDSA verification and nothing is touched")
    func tamperedArtifactRejected() async throws {
        let scenario = try makeScenario(tamper: true)
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        await #expect(throws: UpdateError.self) {
            _ = try await runInstall(scenario)
        }
        #expect(installedVersion(scenario) == "1.0")
    }

    @Test("An app that pins a key refuses Sparkle feeds without a signature")
    func missingSignatureRejected() async throws {
        let scenario = try makeScenario(signArtifact: false)
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        await #expect(throws: UpdateError.self) {
            _ = try await runInstall(scenario)
        }
        #expect(installedVersion(scenario) == "1.0")
    }

    @Test("A pinned key does not block other channels — Gatekeeper decides")
    func pinnedKeyAllowsNonSparkleChannels() async throws {
        // Real-world case: AltTab pins SUPublicEDKey but declares no feed,
        // so its updates arrive via the Homebrew cask URL, unsigned.
        let accepted = try makeScenario(signArtifact: false, releaseSource: .homebrew)
        defer { try? FileManager.default.removeItem(at: accepted.workDir) }
        let phases = try await runInstall(accepted, gatekeeperAccepts: true)
        #expect(phases.last == .finished)
        #expect(installedVersion(accepted) == "2.0")

        let rejected = try makeScenario(signArtifact: false, releaseSource: .homebrew)
        defer { try? FileManager.default.removeItem(at: rejected.workDir) }
        await #expect(throws: UpdateError.self) {
            _ = try await runInstall(rejected, gatekeeperAccepts: false)
        }
        #expect(installedVersion(rejected) == "1.0")
    }

    @Test("A different bundle identifier in the archive is refused")
    func bundleIdentitySwitchRejected() async throws {
        let scenario = try makeScenario(newBundleID: "com.attacker.Impostor")
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        await #expect(throws: UpdateError.self) {
            _ = try await runInstall(scenario)
        }
        #expect(installedVersion(scenario) == "1.0")
    }

    @Test("Downgrades are blocked even when the feed lies about the version")
    func downgradeBlocked() async throws {
        let scenario = try makeScenario(newVersion: "0.9", newBuild: "90")
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        // The feed claims 3.0; the archive actually contains 0.9.
        var lyingRelease = scenario.release
        lyingRelease.version = "3.0"
        lyingRelease.build = "300"
        let key = Curve25519.Signing.PrivateKey()
        // Re-pin so EdDSA passes and the downgrade check is what fails.
        var installed = scenario.installed
        installed.sparklePublicEDKey = key.publicKey.rawRepresentation.base64EncodedString()
        lyingRelease.edSignature = try key.signature(
            for: Data(contentsOf: scenario.release.downloadURL!)
        ).base64EncodedString()

        let installer = UpdateInstaller(gatekeeper: StubGatekeeper(accepts: true))
        await #expect(throws: UpdateError.self) {
            for try await _ in installer.install(lyingRelease, over: installed) {}
        }
        #expect(installedVersion(scenario) == "1.0")
    }

    @Test("Extensionless downloads install — the archive format is sniffed from content")
    func extensionlessArtifact() async throws {
        // Real-world case: VS Code's cask downloads from …/darwin-arm64/stable.
        let scenario = try makeScenario(artifactName: "stable")
        defer { try? FileManager.default.removeItem(at: scenario.workDir) }

        let phases = try await runInstall(scenario)
        #expect(phases.last == .finished)
        #expect(installedVersion(scenario) == "2.0")
    }

    @Test("Without EdDSA, Gatekeeper decides: reject blocks, accept installs")
    func gatekeeperGatesUnsignedFeeds() async throws {
        let rejected = try makeScenario(signArtifact: false, pinEdDSAKey: false)
        defer { try? FileManager.default.removeItem(at: rejected.workDir) }
        await #expect(throws: UpdateError.self) {
            _ = try await runInstall(rejected, gatekeeperAccepts: false)
        }
        #expect(installedVersion(rejected) == "1.0")

        let accepted = try makeScenario(signArtifact: false, pinEdDSAKey: false)
        defer { try? FileManager.default.removeItem(at: accepted.workDir) }
        let phases = try await runInstall(accepted, gatekeeperAccepts: true)
        #expect(phases.last == .finished)
        #expect(installedVersion(accepted) == "2.0")
    }
}
