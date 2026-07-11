import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("ReleaseNotesLoader")
struct ReleaseNotesLoaderTests {
    private func release(
        source: SourceID,
        changelog: String? = nil,
        embeddedNotesURL: URL? = nil
    ) -> ReleaseInfo {
        ReleaseInfo(
            version: "2.0",
            source: source,
            embeddedNotesURL: embeddedNotesURL,
            changelog: changelog
        )
    }

    @Test("Embedded notes are tagged with the source's markup")
    func markupPerSource() {
        #expect(ReleaseNotesLoader.embeddedNotes(of: release(source: .sparkle, changelog: "<h1>New</h1>"))
            == .html("<h1>New</h1>"))
        #expect(ReleaseNotesLoader.embeddedNotes(of: release(source: .github, changelog: "## New"))
            == .markdown("## New"))
        #expect(ReleaseNotesLoader.embeddedNotes(of: release(source: .macAppStore, changelog: "Bug fixes."))
            == .plainText("Bug fixes."))
    }

    @Test("Blank changelogs count as no notes")
    func blankChangelog() {
        #expect(ReleaseNotesLoader.embeddedNotes(of: release(source: .github, changelog: "  \n ")) == nil)
        #expect(ReleaseNotesLoader.embeddedNotes(of: release(source: .github)) == nil)
    }

    @Test("Without embedded notes or a notes document there is nothing to load")
    func nothingToLoad() async throws {
        let loader = ReleaseNotesLoader()
        #expect(try await loader.load(for: release(source: .homebrew)) == nil)
        // A GitHub release's page is not an embeddable document.
        #expect(try await loader.load(for: release(source: .github)) == nil)
    }

    @Test("A Sparkle release notes document is fetched and served as HTML")
    func fetchesSparkleNotesDocument() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "freshly-notes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = directory.appending(path: "notes.html")
        try Data("<p>Fixed things</p>".utf8).write(to: document)

        let loader = ReleaseNotesLoader(session: .shared)
        let notes = try await loader.load(for: release(source: .sparkle, embeddedNotesURL: document))
        #expect(notes == .html("<p>Fixed things</p>"))
    }
}
