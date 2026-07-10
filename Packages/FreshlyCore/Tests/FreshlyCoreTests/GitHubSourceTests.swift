import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("GitHubSource")
struct GitHubSourceTests {
    private func releaseData() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "github-release",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private func app(_ bundleID: String) -> InstalledApp {
        InstalledApp(
            bundleID: bundleID,
            name: "App",
            path: URL(fileURLWithPath: "/Applications/App.app"),
            version: "1.0"
        )
    }

    @Test("A candidate only for apps a definition maps to a repo")
    func applicability() {
        let source = GitHubSource(repos: ["com.example.Mapped": "example/mapped"])
        #expect(source.applicability(for: app("com.example.Mapped")) == .candidate)
        #expect(source.applicability(for: app("com.example.Other")) == .notApplicable)
    }

    @Test("Parses a release: v-stripped tag, notes, page URL, dates")
    func parsesRelease() throws {
        let data = try releaseData()
        let release = try #require(try GitHubSource.release(from: data))
        #expect(release.version == "11.4.3")
        #expect(release.source == .github)
        #expect(release.releaseNotesURL?.absoluteString.contains("releases/tag/v11.4.3") == true)
        #expect(release.changelog?.contains("Bug Fixes") == true)
        #expect(release.publishedAt != nil)
    }

    @Test("Picks the app archive, not the debug-symbol zips")
    func picksRealAsset() throws {
        let data = try releaseData()
        let release = try #require(try GitHubSource.release(from: data))
        #expect(release.downloadURL?.lastPathComponent == "AltTab-11.4.3.zip")
    }

    @Test("Prefers Mac archives and skips other platforms")
    func assetScoring() {
        func asset(_ name: String) -> GitHubSource.Asset {
            GitHubSource.Asset(
                name: name,
                browserDownloadUrl: URL(string: "https://example.com/\(name)"),
                contentType: "application/octet-stream"
            )
        }
        let picked = GitHubSource.pickAsset(from: [
            asset("tool-2.0-linux-x86_64.tar.gz"),
            asset("tool-2.0-windows.zip"),
            asset("tool-2.0-macos-universal.zip"),
            asset("checksums.txt"),
        ])
        #expect(picked?.name == "tool-2.0-macos-universal.zip")

        let nothing = GitHubSource.pickAsset(from: [
            asset("tool-2.0-linux-x86_64.tar.gz"),
            asset("source.tar.gz"),
        ])
        #expect(nothing == nil)
    }

    @Test("Drafts and prereleases yield nothing")
    func drafthandling() throws {
        let draft = Data(#"{"tag_name": "v2.0", "draft": true, "prerelease": false}"#.utf8)
        #expect(try GitHubSource.release(from: draft) == nil)
        let prerelease = Data(#"{"tag_name": "v2.0-beta", "draft": false, "prerelease": true}"#.utf8)
        #expect(try GitHubSource.release(from: prerelease) == nil)
    }

    @Test("Garbage responses fail as parsing errors")
    func garbage() {
        #expect(throws: UpdateError.self) {
            _ = try GitHubSource.release(from: Data("<html>".utf8))
        }
    }
}
