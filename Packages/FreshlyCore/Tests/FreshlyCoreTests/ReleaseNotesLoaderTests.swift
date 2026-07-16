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

    // MARK: - sanitizedNotesHTML

    private static let dangerousMarkers = [
        "<style", "<link", "<base", "@import", "url(", "src=", "href=", "background=", "<img",
    ]

    private func assertSanitized(_ output: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let lowered = output.lowercased()
        for marker in Self.dangerousMarkers {
            #expect(!lowered.contains(marker), "output still contains \(marker): \(output)", sourceLocation: sourceLocation)
        }
    }

    @Test("Ordinary formatting tags survive sanitization")
    func sanitizerPreservesHarmlessMarkup() {
        let input = "<h2>New</h2><p>Fixed a <b>crash</b></p>"
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        #expect(output.contains("<h2>"))
        #expect(output.contains("<p>"))
        #expect(output.contains("<b>crash</b>"))
        assertSanitized(output)
    }

    @Test("A style block with a url() beacon is stripped")
    func sanitizerStripsStyleBlockWithURL() {
        let input = "<style>body{background:url(https://evil.example/x.png)}</style>"
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        assertSanitized(output)
    }

    @Test("A link tag pulling a remote stylesheet is stripped")
    func sanitizerStripsLinkTag() {
        let input = "<link rel=\"stylesheet\" href=\"https://evil.example/x.css\">"
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        assertSanitized(output)
    }

    @Test("An inline style attribute with a url() beacon is stripped, text survives")
    func sanitizerStripsInlineStyleAttribute() {
        let input = "<p style=\"background:url('https://evil.example/beacon')\">hi</p>"
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        assertSanitized(output)
        #expect(output.contains("hi"))
    }

    @Test("An img tag is stripped")
    func sanitizerStripsImgTag() {
        let input = "<img src=\"https://evil.example/track.gif\">"
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        assertSanitized(output)
    }

    @Test("Oversized input is truncated")
    func sanitizerBoundsInputSize() {
        let input = String(repeating: "a", count: 300_000)
        let output = ReleaseNotesLoader.sanitizedNotesHTML(input)
        #expect(output.count <= 200_000)
    }
}
