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

    // Real appcasts (e.g. Dia's) list the full download and its binary
    // deltas as sibling <enclosure> elements in one item. Freshly cannot
    // apply Sparkle deltas, so the parser must ignore them and keep the
    // full enclosure — regardless of order.
    private let deltaFeed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>1.40.0</title>
          <enclosure url="https://example.com/App-1.40.0-83508.zip" sparkle:version="83508" sparkle:shortVersionString="1.40.0" type="application/octet-stream" sparkle:edSignature="FULLsig=="/>
          <enclosure url="https://example.com/App-from-83474-to-83508.delta" sparkle:deltaFrom="83474" type="application/octet-stream" sparkle:edSignature="DELTA1sig=="/>
          <enclosure url="https://example.com/App-from-83438-to-83508.delta" sparkle:deltaFrom="83438" type="application/octet-stream" sparkle:edSignature="DELTA2sig=="/>
        </item>
      </channel>
    </rss>
    """

    @Test("Delta enclosures are skipped; the full update wins")
    func skipsDeltaEnclosures() throws {
        let items = try AppcastParser().parse(Data(deltaFeed.utf8))
        let item = try #require(items.first)
        #expect(item.enclosureURL == URL(string: "https://example.com/App-1.40.0-83508.zip"))
        #expect(item.edSignature == "FULLsig==")
        #expect(item.version == "83508")
    }

    @Test("An item offering only deltas exposes no installable enclosure")
    func deltaOnlyItemHasNoEnclosure() throws {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item><title>x</title>
            <enclosure url="https://example.com/App-from-83474.delta" sparkle:deltaFrom="83474" sparkle:edSignature="D=="/>
          </item></channel>
        </rss>
        """
        let item = try #require(try AppcastParser().parse(Data(feed.utf8)).first)
        #expect(item.enclosureURL == nil)
        #expect(item.edSignature == nil)
    }

    @Test("Malformed XML throws a parsing error")
    func malformedXMLThrows() {
        let garbage = Data("this is not XML at all <<<".utf8)
        #expect(throws: UpdateError.self) {
            try AppcastParser().parse(garbage)
        }
    }
}
