import Foundation
import Testing
@testable import FreshlyModels

@Suite("AppDefinition validation")
struct AppDefinitionTests {
    @Test("A definition with at least one channel is valid")
    func validDefinition() {
        let definition = AppDefinition(
            bundleID: "com.example.App",
            homebrewCask: "example",
            githubRepo: "example/app",
            appcastURL: URL(string: "https://example.com/appcast.xml")
        )
        #expect(definition.validationProblems().isEmpty)
    }

    @Test("A definition pointing nowhere is invalid")
    func pointsNowhere() {
        let definition = AppDefinition(bundleID: "com.example.App")
        #expect(!definition.validationProblems().isEmpty)
    }

    @Test("Plain-http appcasts are rejected")
    func httpAppcastRejected() {
        let definition = AppDefinition(
            bundleID: "com.example.App",
            appcastURL: URL(string: "http://example.com/appcast.xml")
        )
        #expect(definition.validationProblems().contains { $0.contains("https") })
    }

    @Test("Repo references must look like owner/repo")
    func repoFormat() {
        #expect(AppDefinition.isValidRepo("lwouis/alt-tab-macos"))
        #expect(AppDefinition.isValidRepo("a-b.c_d/e.f-g_h"))
        #expect(!AppDefinition.isValidRepo("no-slash"))
        #expect(!AppDefinition.isValidRepo("too/many/parts"))
        #expect(!AppDefinition.isValidRepo("/leading"))
        #expect(!AppDefinition.isValidRepo("spaces in/name"))
    }

    @Test("Unknown version keys are rejected")
    func versionKeyValidation() {
        let definition = AppDefinition(
            bundleID: "com.example.App",
            githubRepo: "example/app",
            quirks: .init(versionKey: "CFBundleWhatever")
        )
        #expect(!definition.validationProblems().isEmpty)
    }
}

@Suite("DefinitionsCatalog")
struct DefinitionsCatalogTests {
    private func makeDirectory(files: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FreshlyDefinitions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        return directory
    }

    @Test("Loads valid files and skips broken ones")
    func lenientLoad() throws {
        let directory = try makeDirectory(files: [
            "com.example.Good.json": #"{"bundleID": "com.example.Good", "githubRepo": "example/good"}"#,
            "broken.json": "not json at all",
            "com.example.Empty.json": #"{"bundleID": "com.example.Empty"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let catalog = DefinitionsCatalog.load(from: directory)
        #expect(catalog.definitions.count == 1)
        #expect(catalog.githubRepos == ["com.example.Good": "example/good"])
    }

    @Test("Strict validation flags every problem, including file naming")
    func strictValidation() throws {
        let directory = try makeDirectory(files: [
            "wrong-name.json": #"{"bundleID": "com.example.Good", "githubRepo": "example/good"}"#,
            "com.example.Empty.json": #"{"bundleID": "com.example.Empty"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let problems = DefinitionsCatalog.validateDirectory(at: directory)
        #expect(problems.count == 2)
        #expect(problems.contains { $0.contains("must be named com.example.Good.json") })
    }

    @Test("An empty directory is a validation error")
    func emptyDirectory() throws {
        let directory = try makeDirectory(files: [:])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!DefinitionsCatalog.validateDirectory(at: directory).isEmpty)
    }

    @Test("Enrichment fills a missing Sparkle feed but never overrides the app's own")
    func enrichmentFeed() throws {
        let catalog = DefinitionsCatalog(definitions: [
            AppDefinition(
                bundleID: "com.example.App",
                appcastURL: URL(string: "https://example.com/appcast.xml")
            )
        ])
        var app = InstalledApp(
            bundleID: "com.example.App",
            name: "Example",
            path: URL(fileURLWithPath: "/Applications/Example.app"),
            version: "1.0"
        )

        let enriched = catalog.enrich(app)
        #expect(enriched.sparkleFeedURL == URL(string: "https://example.com/appcast.xml"))
        #expect(enriched.installChannels.contains(.sparkle))

        app.sparkleFeedURL = URL(string: "https://original.example.com/feed.xml")
        let untouched = catalog.enrich(app)
        #expect(untouched.sparkleFeedURL == URL(string: "https://original.example.com/feed.xml"))
    }

    @Test("The CFBundleVersion quirk swaps the comparable version")
    func enrichmentVersionQuirk() {
        let catalog = DefinitionsCatalog(definitions: [
            AppDefinition(
                bundleID: "com.example.App",
                githubRepo: "example/app",
                quirks: .init(versionKey: "CFBundleVersion")
            )
        ])
        let app = InstalledApp(
            bundleID: "com.example.App",
            name: "Example",
            path: URL(fileURLWithPath: "/Applications/Example.app"),
            version: "1.0",
            build: "4321"
        )
        #expect(catalog.enrich(app).version == "4321")
    }
}
