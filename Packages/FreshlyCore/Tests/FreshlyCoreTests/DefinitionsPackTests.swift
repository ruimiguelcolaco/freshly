import Foundation
import Testing
import FreshlyModels

@Suite("DefinitionsPack")
struct DefinitionsPackTests {
    private let alpha = AppDefinition(bundleID: "com.example.alpha", githubRepo: "example/alpha")
    private let beta = AppDefinition(bundleID: "com.example.beta", homebrewCask: "beta")

    @Test("Packs roundtrip and sort definitions by bundle ID")
    func roundtrip() throws {
        let pack = DefinitionsPack(definitions: [beta, alpha])
        let decoded = try #require(DefinitionsPack.decode(try pack.encoded()))
        #expect(decoded.definitions.map(\.bundleID) == ["com.example.alpha", "com.example.beta"])
        #expect(decoded.schemaVersion == DefinitionsPack.currentSchemaVersion)
    }

    @Test("Encoding is deterministic — CI diffs a fresh pack against the committed one")
    func deterministic() throws {
        let once = try DefinitionsPack(definitions: [beta, alpha]).encoded()
        let again = try DefinitionsPack(definitions: [alpha, beta]).encoded()
        #expect(once == again)
    }

    @Test("Invalid entries are dropped on decode; the rest survive")
    func dropsInvalidEntries() throws {
        let json = """
        {
          "schemaVersion": 1,
          "definitions": [
            {"bundleID": "com.example.alpha", "githubRepo": "example/alpha"},
            {"bundleID": "com.example.broken"}
          ]
        }
        """
        let pack = try #require(DefinitionsPack.decode(Data(json.utf8)))
        #expect(pack.definitions.map(\.bundleID) == ["com.example.alpha"])
    }

    @Test("A pack from a future schema is refused; garbage is refused")
    func refusesUnreadable() {
        let future = """
        {"schemaVersion": 99, "definitions": []}
        """
        #expect(DefinitionsPack.decode(Data(future.utf8)) == nil)
        #expect(DefinitionsPack.decode(Data("not json".utf8)) == nil)
    }

    @Test("Unknown fields are ignored — additive format changes stay compatible")
    func toleratesUnknownFields() throws {
        let json = """
        {
          "schemaVersion": 1,
          "somethingNew": true,
          "definitions": [
            {"bundleID": "com.example.alpha", "githubRepo": "example/alpha", "futureField": 7}
          ]
        }
        """
        let pack = try #require(DefinitionsPack.decode(Data(json.utf8)))
        #expect(pack.definitions.count == 1)
    }
}
