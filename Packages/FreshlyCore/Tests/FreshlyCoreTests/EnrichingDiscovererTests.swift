import Foundation
import Testing
import FreshlyModels
import FreshlyScanner
@testable import FreshlyEngine

private struct FixedDiscoverer: AppDiscovering {
    let list: [InstalledApp]

    func apps() -> AsyncStream<InstalledApp> {
        AsyncStream { continuation in
            for app in list {
                continuation.yield(app)
            }
            continuation.finish()
        }
    }
}

@Suite("EnrichingDiscoverer")
struct EnrichingDiscovererTests {
    @Test("Applies the transform to every discovered app")
    func transformsStream() async {
        let apps = ["com.example.One", "com.example.Two"].map {
            InstalledApp(
                bundleID: $0,
                name: $0,
                path: URL(fileURLWithPath: "/Applications/\($0).app"),
                version: "1.0"
            )
        }
        let catalog = DefinitionsCatalog(definitions: [
            AppDefinition(
                bundleID: "com.example.One",
                appcastURL: URL(string: "https://example.com/one.xml")
            )
        ])
        let discoverer = EnrichingDiscoverer(base: FixedDiscoverer(list: apps)) {
            catalog.enrich($0)
        }

        var seen: [InstalledApp] = []
        for await app in discoverer.apps() {
            seen.append(app)
        }
        #expect(seen.count == 2)
        #expect(seen[0].sparkleFeedURL == URL(string: "https://example.com/one.xml"))
        #expect(seen[1].sparkleFeedURL == nil)
    }
}
