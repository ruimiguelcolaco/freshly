import Foundation

/// A community-contributed fact sheet about where one app publishes its
/// updates — the open equivalent of the proprietary databases commercial
/// updaters kept. One JSON file per app in the repository's `Definitions/`
/// directory, named `<bundleID>.json`.
///
/// Definitions only *point* at update channels. They cannot weaken the
/// install pipeline: whatever they reference still has to pass EdDSA (when
/// the app pins a key), deep code-signature validation, identity and team
/// continuity, downgrade protection, and Gatekeeper policy.
public struct AppDefinition: Sendable, Codable, Hashable {
    public var bundleID: String
    /// Human-readable app name, for catalog readability only.
    public var name: String?
    /// Cask token, when name-based matching cannot find it (or finds an
    /// ambiguous name that Freshly refuses to guess about).
    public var homebrewCask: String?
    /// `owner/repo` whose GitHub Releases carry this app's updates.
    public var githubRepo: String?
    /// Sparkle feed for apps that do not declare `SUFeedURL` in their
    /// `Info.plist` (some configure the feed in code).
    public var appcastURL: URL?
    public var quirks: Quirks?

    public struct Quirks: Sendable, Codable, Hashable {
        /// Which `Info.plist` key holds the comparable version, for apps
        /// whose `CFBundleShortVersionString` is meaningless.
        public var versionKey: String?

        public init(versionKey: String? = nil) {
            self.versionKey = versionKey
        }
    }

    public init(
        bundleID: String,
        name: String? = nil,
        homebrewCask: String? = nil,
        githubRepo: String? = nil,
        appcastURL: URL? = nil,
        quirks: Quirks? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.homebrewCask = homebrewCask
        self.githubRepo = githubRepo
        self.appcastURL = appcastURL
        self.quirks = quirks
    }

    /// Problems that make this definition unacceptable for the catalog.
    /// Empty means valid. The CI validator prints these verbatim.
    public func validationProblems() -> [String] {
        var problems: [String] = []
        if bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("bundleID must not be empty")
        }
        if homebrewCask == nil, githubRepo == nil, appcastURL == nil {
            problems.append("must provide at least one of homebrewCask, githubRepo, appcastURL")
        }
        if let appcastURL, appcastURL.scheme?.lowercased() != "https" {
            problems.append("appcastURL must use https, got \(appcastURL.absoluteString)")
        }
        if let githubRepo, !Self.isValidRepo(githubRepo) {
            problems.append("githubRepo must look like owner/repo, got \(githubRepo)")
        }
        if let key = quirks?.versionKey, key != "CFBundleVersion", key != "CFBundleShortVersionString" {
            problems.append("quirks.versionKey must be CFBundleVersion or CFBundleShortVersionString, got \(key)")
        }
        return problems
    }

    static func isValidRepo(_ repo: String) -> Bool {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

/// The loaded set of definitions, indexed by bundle ID.
public struct DefinitionsCatalog: Sendable {
    public let definitions: [String: AppDefinition]

    public init(definitions: [AppDefinition]) {
        self.definitions = Dictionary(
            definitions.map { ($0.bundleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func definition(for bundleID: String) -> AppDefinition? {
        definitions[bundleID]
    }

    /// bundleID → cask token, for the Homebrew source.
    public var caskTokens: [String: String] {
        definitions.compactMapValues(\.homebrewCask)
    }

    /// bundleID → owner/repo, for the GitHub source.
    public var githubRepos: [String: String] {
        definitions.compactMapValues(\.githubRepo)
    }

    /// Fills in what the scanner could not read from disk: a Sparkle feed
    /// the app declares only in code, or a version-key quirk. Never
    /// overrides what the app itself declares.
    public func enrich(_ app: InstalledApp) -> InstalledApp {
        guard let definition = definitions[app.bundleID] else { return app }
        var enriched = app
        if enriched.sparkleFeedURL == nil, let feed = definition.appcastURL {
            enriched.sparkleFeedURL = feed
            enriched.installChannels.insert(.sparkle)
        }
        if definition.quirks?.versionKey == "CFBundleVersion", let build = enriched.build {
            enriched.version = AppVersion(build)
        }
        return enriched
    }

    /// Lenient load for the app: files that fail to decode are skipped —
    /// a bad definition must never break scanning. CI keeps them out of
    /// the repository via `validateDirectory`.
    public static func load(from directory: URL) -> DefinitionsCatalog {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let definitions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> AppDefinition? in
                guard let data = try? Data(contentsOf: file),
                      let definition = try? JSONDecoder().decode(AppDefinition.self, from: data),
                      definition.validationProblems().isEmpty else {
                    return nil
                }
                return definition
            }
        return DefinitionsCatalog(definitions: definitions)
    }

    /// Strict validation for CI: every problem in every file, including
    /// file-naming (`<bundleID>.json`) violations.
    public static func validateDirectory(at directory: URL) -> [String] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        } catch {
            return ["cannot read directory \(directory.path): \(error.localizedDescription)"]
        }
        guard !files.isEmpty else {
            return ["no definition files found in \(directory.path)"]
        }

        var problems: [String] = []
        for file in files {
            let fileName = file.lastPathComponent
            do {
                let data = try Data(contentsOf: file)
                let definition = try JSONDecoder().decode(AppDefinition.self, from: data)
                problems.append(contentsOf: definition.validationProblems().map { "\(fileName): \($0)" })
                if file.deletingPathExtension().lastPathComponent != definition.bundleID {
                    problems.append("\(fileName): file must be named \(definition.bundleID).json")
                }
            } catch {
                problems.append("\(fileName): not a valid definition — \(error.localizedDescription)")
            }
        }
        return problems
    }
}
