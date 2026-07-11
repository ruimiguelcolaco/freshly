import Foundation
import FreshlyModels
import FreshlySources

/// Refreshes the app-definitions catalog from the repository between app
/// releases: one bulk request for the whole packed catalog (nothing
/// per-app leaves the machine), ETag-cached on disk so an unchanged
/// catalog costs a 304. A failed or unreadable refresh falls back to the
/// last good copy; the bundled catalog remains the floor either way.
public struct RemoteDefinitionsCatalog: Sendable {
    /// The packed catalog as published from the repository's main branch.
    public static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/ruimiguelcolaco/freshly/main/definitions-catalog.json"
    )!

    private let url: URL
    private let session: URLSession
    private let cacheFile: URL
    private let etagFile: URL

    public init(
        url: URL = RemoteDefinitionsCatalog.defaultURL,
        cacheDirectory: URL? = nil,
        session: URLSession = .freshly
    ) {
        let cacheDirectory = cacheDirectory
            ?? URL.applicationSupportDirectory.appending(path: "Freshly/cache", directoryHint: .isDirectory)
        self.url = url
        self.session = session
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cacheFile = cacheDirectory.appending(path: "definitions-catalog.json")
        etagFile = cacheDirectory.appending(path: "definitions-catalog.etag")
    }

    /// The definitions the last successful refresh stored.
    public func cached() -> [AppDefinition] {
        guard let data = try? Data(contentsOf: cacheFile),
              let pack = DefinitionsPack.decode(data) else {
            return []
        }
        return pack.definitions
    }

    /// Fetches the current catalog and returns the freshest definitions
    /// available: the network's when it answers with a readable pack, the
    /// cache's otherwise. Never throws — definitions are an enhancement,
    /// and scanning must proceed without them.
    public func refresh() async -> [AppDefinition] {
        var request = URLRequest(url: url)
        if FileManager.default.fileExists(atPath: cacheFile.path),
           let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(
                etag.trimmingCharacters(in: .whitespacesAndNewlines),
                forHTTPHeaderField: "If-None-Match"
            )
        }

        guard let (data, response) = try? await session.data(for: request) else {
            return cached()
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return cached() // 304 lands here too — the cache is current.
        }
        guard let pack = DefinitionsPack.decode(data) else {
            return cached()
        }

        try? data.write(to: cacheFile, options: .atomic)
        if let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") {
            try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: etagFile)
        }
        return pack.definitions
    }
}
