import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("ElectronSource")
struct ElectronSourceTests {
    /// Notion Calendar's real manifest shape: multiple arch zips and dmgs,
    /// spaces in file names.
    private let notionCalendarManifest = """
    version: 1.138.0
    files:
      - url: Notion Calendar-darwin-arm64-1.138.0.zip
        sha512: M7a9RzDMRxE9kWf6GtoOsj2wGV3nG/AS2AuzN0M+Ccz==
        size: 125982700
      - url: Notion Calendar-darwin-x64-1.138.0.zip
        sha512: Z4pE0kMjbxmPqduAwteg//Mr9c+y+EwOoV/xmn56H14==
        size: 133186122
      - url: Notion Calendar-1.138.0-arm64.dmg
        sha512: aJQgFbhcqi17pAVNO1WTKvX43OMsn3aODuDuC72y7QU==
        size: 121328911
    path: Notion Calendar-darwin-arm64-1.138.0.zip
    sha512: M7a9RzDMRxE9kWf6GtoOsj2wGV3nG/AS2AuzN0M+Ccz==
    releaseDate: '2026-07-07T23:20:34.590Z'
    """

    @Test("Parses a real manifest: version, files, default path, date")
    func parsesManifest() throws {
        let manifest = try #require(ElectronManifest.parse(notionCalendarManifest))
        #expect(manifest.version == AppVersion("1.138.0"))
        #expect(manifest.files.count == 3)
        #expect(manifest.defaultFile?.name == "Notion Calendar-darwin-arm64-1.138.0.zip")
        #expect(manifest.releaseDate != nil)
    }

    @Test("Picks the zip for this architecture, never a disk image")
    func archivePick() throws {
        let manifest = try #require(ElectronManifest.parse(notionCalendarManifest))
        let arm = manifest.archiveFile(architecture: "arm64")
        #expect(arm?.name == "Notion Calendar-darwin-arm64-1.138.0.zip")
        #expect(arm?.sha512 == "M7a9RzDMRxE9kWf6GtoOsj2wGV3nG/AS2AuzN0M+Ccz==")
        let intel = manifest.archiveFile(architecture: "x64")
        #expect(intel?.name == "Notion Calendar-darwin-x64-1.138.0.zip")
    }

    @Test("A single-file manifest with no arch marker still yields its zip")
    func singleFileManifest() throws {
        let manifest = try #require(ElectronManifest.parse("""
        version: 2.0.0
        files:
          - url: App-2.0.0-mac.zip
            sha512: abc==
        path: App-2.0.0-mac.zip
        sha512: abc==
        """))
        #expect(manifest.archiveFile(architecture: "arm64")?.name == "App-2.0.0-mac.zip")
    }

    @Test("Multiline release notes are captured")
    func releaseNotes() throws {
        let manifest = try #require(ElectronManifest.parse("""
        version: 3.1.0
        files:
          - url: App.zip
            sha512: abc==
        releaseNotes: |
          - Fixed a crash
          - Faster startup
        """))
        #expect(manifest.releaseNotes == "- Fixed a crash\n- Faster startup")
    }

    @Test("A manifest without a version is refused")
    func refusesVersionless() {
        #expect(ElectronManifest.parse("files:\n  - url: App.zip") == nil)
        #expect(ElectronManifest.parse("") == nil)
    }

    @Test("Artifact names with spaces resolve next to the manifest, encoded")
    func artifactURLEncoding() throws {
        let manifest = URL(string: "https://example.com/releases/latest-mac.yml")!
        let resolved = ElectronSource.artifactURL(
            for: "Notion Calendar-darwin-arm64-1.138.0.zip",
            relativeTo: manifest
        )
        #expect(resolved?.absoluteString
            == "https://example.com/releases/Notion%20Calendar-darwin-arm64-1.138.0.zip")
    }

    @Test("End to end over file://: manifest fetch to installable release")
    func endToEnd() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "freshly-electron-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestURL = directory.appending(path: "latest-mac.yml")
        try Data(notionCalendarManifest.utf8).write(to: manifestURL)

        let app = InstalledApp(
            bundleID: "com.cron.electron",
            name: "Notion Calendar",
            path: URL(fileURLWithPath: "/Applications/Notion Calendar.app"),
            version: "1.137.0",
            electronManifestURL: manifestURL
        )
        let source = ElectronSource(session: .shared)
        #expect(source.applicability(for: app) == .authoritative)

        let release = try #require(try await source.latestRelease(for: app))
        #expect(release.source == .electron)
        #expect(release.version == AppVersion("1.138.0"))
        #expect(release.sha512 != nil)
        #expect(release.isNewer(than: app))
        let expectedName = ElectronManifest.currentArchitecture == "arm64"
            ? "Notion%20Calendar-darwin-arm64-1.138.0.zip"
            : "Notion%20Calendar-darwin-x64-1.138.0.zip"
        #expect(release.downloadURL?.lastPathComponent.contains("Notion Calendar") == true)
        #expect(release.downloadURL?.absoluteString.hasSuffix(expectedName) == true)
    }

    @Test("Apps without a manifest URL are not applicable")
    func notApplicable() {
        let app = InstalledApp(
            bundleID: "com.example.plain",
            name: "Plain",
            path: URL(fileURLWithPath: "/Applications/Plain.app"),
            version: "1.0"
        )
        #expect(ElectronSource().applicability(for: app) == .notApplicable)
    }
}
