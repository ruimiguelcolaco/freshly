import Foundation
import FreshlyModels

/// Checks apps against the Homebrew cask index, matching by the `.app`
/// artifact file name. Authoritative when the cask is actually installed
/// via brew (present in the Caskroom); a plain candidate when a cask merely
/// exists for a manually installed app.
///
/// Matching is deliberately conservative — a wrong match means nagging the
/// user about an update for a different app:
/// - App names claimed by more than one cask are ambiguous and excluded
///   (app definitions, milestone 5, will resolve these precisely).
/// - Apple software (`com.apple.*`, including Safari Web Apps) never ships
///   via cask; any name match is a collision.
/// - Freshness uses the cask's marketing version only: the part after the
///   comma in `"2.2.1,5287492581195776"` is brew's artifact bookkeeping and
///   does not reliably correspond to the app's `CFBundleVersion`.
///
/// Built from an already-loaded catalog so that `applicability(for:)` stays
/// cheap and offline, as the `UpdateSource` contract requires — the catalog
/// fetch happens once per scan, before the registry is assembled.
public struct HomebrewSource: UpdateSource {
    public let id = SourceID.homebrew

    /// Lowercased app file name (e.g. `"firefox.app"`) → cask.
    private let entriesByAppName: [String: CaskEntry]
    private let entriesByToken: [String: CaskEntry]
    /// bundleID → cask token pins from app definitions: explicit, reviewed
    /// mappings that bypass name matching (and its ambiguity exclusions).
    private let definitionTokens: [String: String]
    private let installedTokens: Set<String>

    public init(
        entries: [CaskEntry],
        installedCaskTokens: Set<String>,
        definitionTokens: [String: String] = [:]
    ) {
        var byName: [String: CaskEntry] = [:]
        var ambiguous: Set<String> = []
        for entry in entries {
            for appName in entry.appNames {
                let key = appName.lowercased()
                if let existing = byName[key], existing.token != entry.token {
                    ambiguous.insert(key)
                } else {
                    byName[key] = entry
                }
            }
        }
        for key in ambiguous {
            byName.removeValue(forKey: key)
        }
        entriesByAppName = byName
        entriesByToken = Dictionary(entries.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        self.definitionTokens = definitionTokens
        installedTokens = installedCaskTokens
    }

    public func applicability(for app: InstalledApp) -> SourceApplicability {
        guard let entry = entry(for: app) else { return .notApplicable }
        return installedTokens.contains(entry.token) ? .authoritative : .candidate
    }

    public func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        guard applicability(for: app) != .notApplicable, let entry = entry(for: app) else { return nil }
        guard entry.version.lowercased() != "latest" else {
            // Rolling casks are uncomparable; report nothing.
            return nil
        }
        return ReleaseInfo(
            version: Self.marketingVersion(of: entry.version),
            caskToken: entry.token,
            source: .homebrew,
            downloadURL: entry.downloadURL,
            releaseNotesURL: entry.homepage
        )
    }

    /// The comparable part of a cask version. Brew appends artifact
    /// bookkeeping the app's own version strings never carry: a comma
    /// suffix (`"2.2.1,5287…"`), and for some casks a trailing build hash
    /// (`"3.6.2-57f0b637"` — GitHub Desktop, whose installed app says
    /// plain `3.6.2`). Both would read as phantom updates that then fail
    /// the installer's downgrade check. Genuine prerelease tags survive:
    /// `"3.6.3-beta3-7609109d"` → `"3.6.3-beta3"`.
    static func marketingVersion(of raw: String) -> AppVersion {
        var version = raw
        if let comma = version.firstIndex(of: ",") {
            version = String(version[..<comma])
        }
        while let dash = version.lastIndex(of: "-") {
            let suffix = version[version.index(after: dash)...]
            let isHexHash = suffix.count >= 7
                && suffix.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
            guard isHexHash else { break }
            version = String(version[..<dash])
        }
        return AppVersion(version)
    }

    private func entry(for app: InstalledApp) -> CaskEntry? {
        if let token = definitionTokens[app.bundleID] {
            return entriesByToken[token]
        }
        guard !app.bundleID.hasPrefix("com.apple.") else { return nil }
        return entriesByAppName[app.path.lastPathComponent.lowercased()]
    }
}
