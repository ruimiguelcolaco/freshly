import Foundation
import Testing
import FreshlyModels
@testable import FreshlyEngine

@Suite("RemoteDefinitionsCatalog")
struct RemoteDefinitionsCatalogTests {
    private let alpha = AppDefinition(bundleID: "com.example.alpha", githubRepo: "example/alpha")

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "freshly-remote-defs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePack(_ definitions: [AppDefinition], to url: URL) throws {
        try DefinitionsPack(definitions: definitions).encoded().write(to: url)
    }

    @Test("A refresh stores the catalog; cached() serves it afterwards")
    func refreshStores() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let published = directory.appending(path: "published.json")
        try writePack([alpha], to: published)

        let cacheDirectory = directory.appending(path: "cache", directoryHint: .isDirectory)
        let remote = RemoteDefinitionsCatalog(url: published, cacheDirectory: cacheDirectory, session: .shared)

        let fetched = await remote.refresh()
        #expect(fetched == [alpha])
        #expect(remote.cached() == [alpha])
    }

    @Test("An unreachable catalog falls back to the cache")
    func unreachableFallsBack() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let published = directory.appending(path: "published.json")
        try writePack([alpha], to: published)
        let cacheDirectory = directory.appending(path: "cache", directoryHint: .isDirectory)

        _ = await RemoteDefinitionsCatalog(url: published, cacheDirectory: cacheDirectory, session: .shared)
            .refresh()
        try FileManager.default.removeItem(at: published)

        let offline = RemoteDefinitionsCatalog(url: published, cacheDirectory: cacheDirectory, session: .shared)
        let fetched = await offline.refresh()
        #expect(fetched == [alpha])
    }

    @Test("An unreadable reply never overwrites the last good cache")
    func unreadableKeepsCache() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let published = directory.appending(path: "published.json")
        try writePack([alpha], to: published)
        let cacheDirectory = directory.appending(path: "cache", directoryHint: .isDirectory)

        _ = await RemoteDefinitionsCatalog(url: published, cacheDirectory: cacheDirectory, session: .shared)
            .refresh()
        try Data("not json".utf8).write(to: published)

        let corrupted = RemoteDefinitionsCatalog(url: published, cacheDirectory: cacheDirectory, session: .shared)
        let fetched = await corrupted.refresh()
        #expect(fetched == [alpha])
        #expect(corrupted.cached() == [alpha])
    }

    @Test("Without network and cache there are simply no remote definitions")
    func emptyWithoutAnything() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = RemoteDefinitionsCatalog(
            url: directory.appending(path: "missing.json"),
            cacheDirectory: directory.appending(path: "cache", directoryHint: .isDirectory),
            session: .shared
        )
        let fetched = await remote.refresh()
        #expect(fetched.isEmpty)
    }

    @Test("Merged with the bundled catalog, the remote definition wins")
    func remoteWinsMerge() {
        let bundled = AppDefinition(bundleID: "com.example.alpha", githubRepo: "example/old-home")
        let other = AppDefinition(bundleID: "com.example.beta", homebrewCask: "beta")
        let merged = DefinitionsCatalog(definitions: [alpha] + [bundled, other])
        #expect(merged.definition(for: "com.example.alpha")?.githubRepo == "example/alpha")
        #expect(merged.definition(for: "com.example.beta") != nil)
    }
}
