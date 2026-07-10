import Foundation
import Testing
@testable import FreshlyModels

@Suite("ReleaseInfo freshness")
struct ReleaseInfoTests {
    private func app(version: AppVersion, build: String?) -> InstalledApp {
        InstalledApp(
            bundleID: "com.example.App",
            name: "Example",
            path: URL(fileURLWithPath: "/Applications/Example.app"),
            version: version,
            build: build
        )
    }

    @Test("Matching builds mean up to date even when the feed decorates the marketing version")
    func decoratedMarketingVersionIsNotAnUpdate() {
        // Real-world case: installed 1.39.0 (CFBundleVersion 83141); the
        // appcast advertises shortVersionString "1.39.0 (83141)" with
        // sparkle:version 83141. Marketing strings differ, builds match.
        let release = ReleaseInfo(version: "1.39.0 (83141)", build: "83141", source: .sparkle)
        #expect(!release.isNewer(than: app(version: "1.39.0", build: "83141")))
    }

    @Test("A higher build is an update even with an equal marketing version")
    func higherBuildWins() {
        let release = ReleaseInfo(version: "1.39.0", build: "83200", source: .sparkle)
        #expect(release.isNewer(than: app(version: "1.39.0", build: "83141")))
    }

    @Test("Without builds, marketing versions decide")
    func fallsBackToMarketingVersion() {
        let release = ReleaseInfo(version: "2.0", source: .sparkle)
        #expect(release.isNewer(than: app(version: "1.9", build: "900")))
        #expect(!release.isNewer(than: app(version: "2.0", build: nil)))
    }
}
