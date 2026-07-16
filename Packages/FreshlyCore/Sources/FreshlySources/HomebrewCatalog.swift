import Foundation
import FreshlyModels

/// One cask from the Homebrew index, reduced to what Freshly needs.
public struct CaskEntry: Sendable, Hashable, Codable {
    public let token: String
    /// Raw cask version; may be `"1.2.3,4567"` (version, build) or `"latest"`.
    public let version: String
    /// `.app` artifact file names this cask installs, e.g. `"Firefox.app"`.
    public let appNames: [String]
    public let homepage: URL?
    /// The vendor artifact the cask downloads — usable by Freshly's own
    /// verified install pipeline when the app was not installed via brew.
    public let downloadURL: URL?

    public init(token: String, version: String, appNames: [String], homepage: URL?, downloadURL: URL?) {
        self.token = token
        self.version = version
        self.appNames = appNames
        self.homepage = homepage
        self.downloadURL = downloadURL
    }
}

/// Fetches and caches the public Homebrew cask index.
///
/// Privacy: the *entire* index is downloaded (one request, ETag-cached on
/// disk) and matching happens locally — the Homebrew project never learns
/// which apps the user has. No local brew installation is required to
/// check versions.
public struct HomebrewCatalog: Sendable {
    private static let indexURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    private let session: URLSession
    private let cacheDirectory: URL

    public init(session: URLSession = .freshly, cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory
            ?? URL.applicationSupportDirectory.appending(path: "Freshly/cache", directoryHint: .isDirectory)
    }

    public func loadEntries() async throws -> [CaskEntry] {
        let cacheFile = cacheDirectory.appending(path: "cask-index.json")
        let etagFile = cacheDirectory.appending(path: "cask-index.etag")

        var request = URLRequest(url: Self.indexURL)
        if FileManager.default.fileExists(atPath: cacheFile.path),
           let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 304, let cached = try? Data(contentsOf: cacheFile) {
                return try Self.parseEntries(from: cached)
            }
            guard let http, (200..<300).contains(http.statusCode) else {
                throw UpdateError(.sourceHTTPStatus(.homebrew, status: http?.statusCode ?? -1))
            }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: .atomic)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
            }
            return try Self.parseEntries(from: data)
        } catch {
            // Offline or the fetch failed: a stale index beats no index.
            if let cached = try? Data(contentsOf: cacheFile),
               let entries = try? Self.parseEntries(from: cached) {
                return entries
            }
            if let updateError = error as? UpdateError { throw updateError }
            throw UpdateError(.sourceRequestFailed(.homebrew, detail: error.localizedDescription))
        }
    }

    /// Lenient parse of the index: entries without a token or version are
    /// dropped; artifact shapes we do not understand are ignored.
    public static func parseEntries(from data: Data) throws -> [CaskEntry] {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw UpdateError(.sourceResponseUnreadable(.homebrew, detail: nil))
        }
        guard let casks = parsed as? [[String: Any]] else {
            throw UpdateError(.sourceResponseUnreadable(.homebrew, detail: nil))
        }

        return casks.compactMap { cask in
            guard let token = cask["token"] as? String,
                  let version = cask["version"] as? String else {
                return nil
            }
            var appNames: [String] = []
            for artifact in (cask["artifacts"] as? [[String: Any]]) ?? [] {
                for item in (artifact["app"] as? [Any]) ?? [] {
                    if let name = item as? String, name.hasSuffix(".app") {
                        appNames.append(name)
                    }
                }
            }
            return CaskEntry(
                token: token,
                version: version,
                appNames: appNames,
                homepage: (cask["homepage"] as? String).flatMap(URL.init(string:)),
                downloadURL: (cask["url"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    /// Distinct cask tokens whose `.app` artifact matches `appFileName`
    /// (e.g. "Firefox.app"), case-insensitive. Zero = no cask; one =
    /// a confident suggestion; more than one = ambiguous (the caller should
    /// surface all and let the human choose).
    public static func caskTokens(matchingAppNamed appFileName: String, in entries: [CaskEntry]) -> [String] {
        let needle = appFileName.lowercased()
        var tokens: [String] = []
        for entry in entries where entry.appNames.contains(where: { $0.lowercased() == needle }) {
            if !tokens.contains(entry.token) { tokens.append(entry.token) }
        }
        return tokens
    }
}

/// Local Homebrew cask bookkeeping — which casks are installed via brew.
public struct Caskroom: Sendable {
    public let root: URL

    public static let standardLocations = [
        URL(fileURLWithPath: "/opt/homebrew/Caskroom", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/Caskroom", isDirectory: true),
    ]

    public init(root: URL) {
        self.root = root
    }

    public static func detect() -> Caskroom? {
        var isDirectory: ObjCBool = false
        return standardLocations.first {
            FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }.map(Caskroom.init)
    }

    public func installedTokens() -> Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return Set(entries.map(\.lastPathComponent))
    }
}
