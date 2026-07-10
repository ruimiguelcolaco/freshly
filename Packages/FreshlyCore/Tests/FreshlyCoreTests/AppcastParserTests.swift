import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("AppcastParser")
struct AppcastParserTests {
    private func fixtureData() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "sparkle-appcast",
            withExtension: "xml",
            subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    @Test("Parses every item in the feed")
    func parsesAllItems() throws {
        let items = try AppcastParser().parse(fixtureData())
        #expect(items.count == 4)
    }

    @Test("Reads sparkle elements from an item")
    func readsSparkleElements() throws {
        let items = try AppcastParser().parse(fixtureData())
        let latest = try #require(items.first)
        #expect(latest.shortVersionString == "2.1")
        #expect(latest.version == "2100")
        #expect(latest.minimumSystemVersion == "13.0")
        #expect(latest.enclosureURL == URL(string: "https://example.com/downloads/DemoApp-2.1.zip"))
        #expect(latest.releaseNotesURL == URL(string: "https://example.com/notes/2.1.html"))
        #expect(latest.link == URL(string: "https://example.com/release-2.1"))
        #expect(latest.channel == nil)
        #expect(latest.pubDate != nil)
        #expect(latest.edSignature == "MEUCIDdemo/signature==")
    }

    @Test("Reads CDATA release notes")
    func readsCDATADescription() throws {
        let items = try AppcastParser().parse(fixtureData())
        let notes = try #require(items.first?.descriptionHTML)
        #expect(notes.contains("What's new in 2.1"))
    }

    @Test("Falls back to version attributes on the enclosure")
    func versionAttributesOnEnclosure() throws {
        let items = try AppcastParser().parse(fixtureData())
        let legacyItem = try #require(items.last)
        #expect(legacyItem.shortVersionString == "2.0")
        #expect(legacyItem.version == "2000")
    }

    @Test("Reads the channel of non-default-channel items")
    func readsChannel() throws {
        let items = try AppcastParser().parse(fixtureData())
        #expect(items[1].channel == "beta")
    }

    @Test("Malformed XML throws a parsing error")
    func malformedXMLThrows() {
        let garbage = Data("this is not XML at all <<<".utf8)
        #expect(throws: UpdateError.self) {
            try AppcastParser().parse(garbage)
        }
    }
}
