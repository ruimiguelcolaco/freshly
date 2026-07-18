import Testing
import FreshlyModels
@testable import FreshlyEngine

@Suite("DefinitionsProvider.merge")
struct DefinitionsProviderTests {
    private func def(_ bundleID: String, cask: String) -> AppDefinition {
        AppDefinition(bundleID: bundleID, homebrewCask: cask)
    }

    @Test("An empty remote leaves the bundled floor untouched")
    func emptyRemoteFallsBack() {
        let bundled = DefinitionsCatalog(definitions: [def("com.a", cask: "a")])
        let merged = DefinitionsProvider.merge(remote: [], over: bundled)
        #expect(merged.definitions.count == 1)
        #expect(merged.definition(for: "com.a")?.homebrewCask == "a")
    }

    @Test("Remote overrides the bundled definition for the same app")
    func remoteOverridesPerBundleID() {
        let bundled = DefinitionsCatalog(definitions: [
            def("com.a", cask: "bundled"),
            def("com.b", cask: "b"),
        ])
        let merged = DefinitionsProvider.merge(
            remote: [def("com.a", cask: "remote")],
            over: bundled
        )
        #expect(merged.definition(for: "com.a")?.homebrewCask == "remote")
        #expect(merged.definition(for: "com.b")?.homebrewCask == "b")
        #expect(merged.definitions.count == 2)
    }
}
