import Foundation
import Testing
import FreshlyModels
@testable import FreshlySources

@Suite("MacAppStoreSource")
struct MacAppStoreSourceTests {
    private func lookupData() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "itunes-lookup",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private func app(channels: Set<SourceID>) -> InstalledApp {
        InstalledApp(
            bundleID: "com.example.DemoApp",
            name: "Demo App",
            path: URL(fileURLWithPath: "/Applications/Demo App.app"),
            version: "3.0",
            installChannels: channels
        )
    }

    @Test("Authoritative only for apps with a Mac App Store receipt")
    func applicability() {
        let source = MacAppStoreSource()
        #expect(source.applicability(for: app(channels: [.macAppStore])) == .authoritative)
        #expect(source.applicability(for: app(channels: [.macAppStore, .sparkle])) == .authoritative)
        #expect(source.applicability(for: app(channels: [.sparkle])) == .notApplicable)
        #expect(source.applicability(for: app(channels: [])) == .notApplicable)
    }

    @Test("Parses the mac-software result, ignoring the iOS twin")
    func parsesMacResult() throws {
        let data = try lookupData()
        let release = try #require(try MacAppStoreSource.release(
            fromLookup: data,
            bundleID: "com.example.DemoApp",
            runningOn: "26.1"
        ))
        #expect(release.version == "3.2.1")
        #expect(release.source == .macAppStore)
        #expect(release.downloadURL == nil)
        #expect(release.releaseNotesURL?.absoluteString.contains("id222222222") == true)
        #expect(release.changelog?.contains("Faster syncing") == true)
        #expect(release.publishedAt != nil)
        #expect(release.minimumOSVersion == "14.0")
    }

    @Test("An app missing from the store yields no release")
    func missingApp() throws {
        let empty = Data(#"{"resultCount": 0, "results": []}"#.utf8)
        let release = try MacAppStoreSource.release(
            fromLookup: empty,
            bundleID: "com.example.Gone",
            runningOn: "26.1"
        )
        #expect(release == nil)
    }

    @Test("A store version needing a newer macOS is not reported")
    func minimumOSFiltering() throws {
        let data = try lookupData()
        let release = try MacAppStoreSource.release(
            fromLookup: data,
            bundleID: "com.example.DemoApp",
            runningOn: "13.5"
        )
        #expect(release == nil)
    }

    @Test("Garbage responses fail as parsing errors")
    func garbageResponse() {
        #expect(throws: UpdateError.self) {
            _ = try MacAppStoreSource.release(
                fromLookup: Data("not json".utf8),
                bundleID: "com.example.DemoApp",
                runningOn: "26.1"
            )
        }
    }
}
