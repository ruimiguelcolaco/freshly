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

    @Test("A newer marketing version is not a downgrade even when builds are equal")
    func staticBuildIsNotADowngrade() {
        // Real-world case: Glaze ships CFBundleVersion "0" on every release,
        // so 0.9.1→0.10.0 has equal builds. The extracted bundle carries a
        // clean marketing version, so it must not be blocked as a downgrade.
        let extracted = ReleaseInfo(version: "0.10.0", build: "0", source: .homebrew)
        #expect(!extracted.isDowngrade(over: app(version: "0.9.1", build: "0")))
    }

    @Test("A genuinely older bundle is a downgrade")
    func olderMarketingIsADowngrade() {
        let extracted = ReleaseInfo(version: "0.9.0", build: "0", source: .sparkle)
        #expect(extracted.isDowngrade(over: app(version: "0.9.1", build: "0")))
    }

    @Test("At an equal marketing version, a lower build is a downgrade; a higher one is not")
    func buildBreaksTheMarketingTie() {
        let older = ReleaseInfo(version: "1.40.0", build: "83317", source: .sparkle)
        #expect(older.isDowngrade(over: app(version: "1.40.0", build: "83508")))
        let newer = ReleaseInfo(version: "1.40.0", build: "83508", source: .sparkle)
        #expect(!newer.isDowngrade(over: app(version: "1.40.0", build: "83317")))
    }

    @Test("Reinstalling the same version is not a downgrade")
    func sameVersionIsNotADowngrade() {
        let same = ReleaseInfo(version: "1.0", build: "100", source: .sparkle)
        #expect(!same.isDowngrade(over: app(version: "1.0", build: "100")))
    }
}
