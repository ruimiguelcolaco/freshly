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
    private let fetcher: CachedFetcher

    public init(
        url: URL = RemoteDefinitionsCatalog.defaultURL,
        cacheDirectory: URL? = nil,
        session: URLSession = .freshly
    ) {
        let cacheDirectory = cacheDirectory
            ?? URL.applicationSupportDirectory.appending(path: "Freshly/cache", directoryHint: .isDirectory)
        self.url = url
        fetcher = CachedFetcher(session: session, cacheDirectory: cacheDirectory)
    }

    /// The definitions the last successful refresh stored.
    public func cached() -> [AppDefinition] {
        (try? fetcher.cachedValue(for: "definitions-catalog") { response in
            guard let pack = DefinitionsPack.decode(response.data) else {
                throw CachedFetchError.cacheUnavailable
            }
            return pack.definitions
        }) ?? []
    }

    /// Fetches the current catalog and returns the freshest definitions
    /// available: the network's when it answers with a readable pack, the
    /// cache's otherwise. Never throws — definitions are an enhancement,
    /// and scanning must proceed without them.
    public func refresh() async -> [AppDefinition] {
        do {
            return try await fetcher.fetch(
                URLRequest(url: url),
                cacheKey: "definitions-catalog",
                fallbackOnHTTPError: true
            ) { response in
                guard let pack = DefinitionsPack.decode(response.data) else {
                    throw CachedFetchError.cacheUnavailable
                }
                return pack.definitions
            }
        } catch {
            return cached()
        }
    }
}
