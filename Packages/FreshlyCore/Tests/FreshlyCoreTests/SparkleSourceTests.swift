import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("SparkleSource")
struct SparkleSourceTests {
    @Test("Authoritative only when the app declares a feed")
    func applicability() {
        let source = SparkleSource()
        var app = InstalledApp(
            bundleID: "com.example.App",
            name: "Example",
            path: URL(fileURLWithPath: "/Applications/Example.app"),
            version: "1.0"
        )
        #expect(source.applicability(for: app) == .notApplicable)

        app.sparkleFeedURL = URL(string: "https://example.com/appcast.xml")
        #expect(source.applicability(for: app) == .authoritative)
    }

    @Test("Picks the newest runnable release from a real-world feed")
    func picksLatestEligible() throws {
        let url = try #require(Bundle.module.url(
            forResource: "sparkle-appcast",
            withExtension: "xml",
            subdirectory: "Fixtures"
        ))
        let items = try AppcastParser().parse(Data(contentsOf: url))

        // The beta-channel 3.0b1 and the future-macOS-only 9.9 must lose to 2.1.
        let picked = try #require(SparkleSource.pickLatest(from: items, runningOn: "26.1"))
        #expect(picked.shortVersionString == "2.1")
    }

    @Test("An older macOS keeps releases it cannot run out of the pick")
    func respectsMinimumSystemVersion() throws {
        var current = AppcastItem()
        current.shortVersionString = "5.0"
        current.minimumSystemVersion = "15.0"
        var tooNew = AppcastItem()
        tooNew.shortVersionString = "6.0"
        tooNew.minimumSystemVersion = "26.0"

        let picked = SparkleSource.pickLatest(from: [current, tooNew], runningOn: "15.5")
        #expect(picked?.shortVersionString == "5.0")
    }

    @Test("Plain-http feed URLs are upgraded to https")
    func httpsUpgrade() throws {
        let insecure = try #require(URL(string: "http://example.com/appcast.xml"))
        #expect(SparkleSource.enforcingHTTPS(insecure).scheme == "https")

        let secure = try #require(URL(string: "https://example.com/appcast.xml"))
        #expect(SparkleSource.enforcingHTTPS(secure) == secure)
    }
}
