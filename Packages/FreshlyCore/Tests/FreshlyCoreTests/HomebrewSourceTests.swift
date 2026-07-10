import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("HomebrewCatalog")
struct HomebrewCatalogTests {
    private func entries() throws -> [CaskEntry] {
        let url = try #require(Bundle.module.url(
            forResource: "homebrew-casks",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try HomebrewCatalog.parseEntries(from: Data(contentsOf: url))
    }

    @Test("Parses tokens, versions, app artifacts, and URLs from the index")
    func parsesIndex() throws {
        let parsed = try entries()
        #expect(parsed.count == 7)

        let firefox = try #require(parsed.first { $0.token == "firefox" })
        #expect(firefox.version == "140.0.4")
        #expect(firefox.appNames == ["Firefox.app"])
        #expect(firefox.downloadURL?.absoluteString.contains("mozilla") == true)
        #expect(firefox.homepage != nil)

        let cli = try #require(parsed.first { $0.token == "no-app-artifact" })
        #expect(cli.appNames.isEmpty)
    }

    @Test("Garbage data fails as a parsing error")
    func garbageIndex() {
        #expect(throws: UpdateError.self) {
            _ = try HomebrewCatalog.parseEntries(from: Data("nope".utf8))
        }
    }
}

@Suite("HomebrewSource")
struct HomebrewSourceTests {
    private func makeSource(installed: Set<String> = []) throws -> HomebrewSource {
        let url = try #require(Bundle.module.url(
            forResource: "homebrew-casks",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let entries = try HomebrewCatalog.parseEntries(from: Data(contentsOf: url))
        return HomebrewSource(entries: entries, installedCaskTokens: installed)
    }

    private func app(
        fileName: String,
        bundleID: String? = nil,
        version: AppVersion = "1.0",
        build: String? = nil
    ) -> InstalledApp {
        InstalledApp(
            bundleID: bundleID ?? "com.example.\(fileName)",
            name: fileName,
            path: URL(fileURLWithPath: "/Applications/\(fileName)"),
            version: version,
            build: build
        )
    }

    @Test("Authoritative for brew-installed casks, candidate otherwise")
    func applicability() throws {
        let source = try makeSource(installed: ["firefox"])
        #expect(source.applicability(for: app(fileName: "Firefox.app")) == .authoritative)
        #expect(source.applicability(for: app(fileName: "iTerm.app")) == .candidate)
        #expect(source.applicability(for: app(fileName: "Unknown.app")) == .notApplicable)
    }

    @Test("Matching is by app file name, case-insensitively")
    func caseInsensitiveMatch() throws {
        let source = try makeSource()
        #expect(source.applicability(for: app(fileName: "firefox.APP")) == .candidate)
    }

    @Test("Reports the cask version with token and download URL")
    func reportsRelease() async throws {
        let source = try makeSource()
        let release = try #require(try await source.latestRelease(for: app(fileName: "iTerm.app")))
        #expect(release.version == "3.5.14")
        #expect(release.caskToken == "iterm2")
        #expect(release.source == .homebrew)
        #expect(release.downloadURL?.absoluteString.contains("iterm2.com") == true)
    }

    @Test("Freshness uses the marketing version only — brew's comma suffix is not comparable")
    func commaSuffixIgnored() async throws {
        let source = try makeSource()
        let release = try #require(try await source.latestRelease(
            for: app(fileName: "Builder.app", version: "2.0.1", build: "4567")
        ))
        #expect(release.version == "2.0.1")
        #expect(release.build == nil)
        // Same marketing version → up to date, whatever the builds claim.
        // (Real-world case: cask "2.2.1,5287492581195776" vs installed
        // CFBundleVersion "2.2.1" — different bookkeeping schemes.)
        #expect(!release.isNewer(than: app(fileName: "Builder.app", version: "2.0.1", build: "1")))
        #expect(release.isNewer(than: app(fileName: "Builder.app", version: "2.0.0", build: "4567")))
    }

    @Test("Apple software never matches casks — Safari Web Apps stay out")
    func appleBundlesExcluded() throws {
        let source = try makeSource()
        let webApp = app(
            fileName: "Firefox.app",
            bundleID: "com.apple.Safari.WebApp.1234-ABCD"
        )
        #expect(source.applicability(for: webApp) == .notApplicable)
    }

    @Test("App names claimed by several casks are ambiguous and excluded")
    func ambiguousNamesExcluded() throws {
        let source = try makeSource(installed: ["shade-one"])
        #expect(source.applicability(for: app(fileName: "Shade.app")) == .notApplicable)
    }

    @Test("A definition's cask pin resolves what name matching refuses to guess")
    func definitionPinBeatsAmbiguity() async throws {
        let url = try #require(Bundle.module.url(
            forResource: "homebrew-casks", withExtension: "json", subdirectory: "Fixtures"
        ))
        let entries = try HomebrewCatalog.parseEntries(from: Data(contentsOf: url))
        let source = HomebrewSource(
            entries: entries,
            installedCaskTokens: [],
            definitionTokens: ["com.example.Shade.app": "shade-two"]
        )

        let shade = app(fileName: "Shade.app") // bundleID com.example.Shade.app
        #expect(source.applicability(for: shade) == .candidate)
        let release = try #require(try await source.latestRelease(for: shade))
        #expect(release.caskToken == "shade-two")
        #expect(release.version == "0.9.1")
    }

    @Test("Rolling 'latest' casks report nothing")
    func rollingCasksSkipped() async throws {
        let source = try makeSource()
        let release = try await source.latestRelease(for: app(fileName: "Rolling.app"))
        #expect(release == nil)
    }

    @Test("Marketing-version extraction handles the edge shapes")
    func versionSplitting() {
        #expect(HomebrewSource.marketingVersion(of: "1.2.3") == AppVersion("1.2.3"))
        #expect(HomebrewSource.marketingVersion(of: "1.2.3,4567") == AppVersion("1.2.3"))
        #expect(HomebrewSource.marketingVersion(of: "1.2.3,") == AppVersion("1.2.3"))
    }
}

@Suite("Per-app source override")
struct SourceOverrideTests {
    private let app = InstalledApp(
        bundleID: "com.example.App",
        name: "Example",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        version: "1.0"
    )

    private var status: AppUpdateStatus {
        AppUpdateStatus(app: app, state: .outdated(
            best: ReleaseInfo(version: "2.0", source: .sparkle),
            alternatives: [
                ReleaseInfo(version: "2.0", caskToken: "example", source: .homebrew),
                ReleaseInfo(version: "1.0", source: .github),
            ]
        ))
    }

    @Test("Preferring an alternative source re-ranks it as primary")
    func rerank() throws {
        let preferred = status.preferring(.homebrew)
        guard case .outdated(let best, let alternatives) = preferred.state else {
            Issue.record("expected outdated")
            return
        }
        #expect(best.source == .homebrew)
        #expect(alternatives.map(\.source) == [.sparkle, .github])
    }

    @Test("An override to a not-newer release is ignored")
    func notNewerIgnored() {
        let preferred = status.preferring(.github)
        guard case .outdated(let best, _) = preferred.state else {
            Issue.record("expected outdated")
            return
        }
        #expect(best.source == .sparkle)
    }

    @Test("No override, unknown source, or non-outdated states are no-ops")
    func noOps() {
        #expect(status.preferring(nil) == status)
        #expect(status.preferring(.macAppStore) == status)
        let upToDate = AppUpdateStatus(app: app, state: .upToDate)
        #expect(upToDate.preferring(.homebrew) == upToDate)
    }
}
