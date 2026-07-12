import Foundation
import FreshlyModels

/// The current release published on an electron-updater channel, parsed
/// from its manifest (`latest-mac.yml` or a channel variant).
public struct ElectronManifest: Sendable, Hashable {
    public struct File: Sendable, Hashable {
        public var name: String
        public var sha512: String?
    }

    public var version: AppVersion
    public var files: [File]
    /// The manifest's own default artifact (top-level `path`/`sha512`).
    public var defaultFile: File?
    public var releaseDate: Date?
    public var releaseNotes: String?

    /// Line-based parse of the manifest subset Freshly needs. Unknown
    /// keys are ignored; a manifest without a version is no manifest.
    public static func parse(_ text: String) -> ElectronManifest? {
        var top: [String: String] = [:]
        var files: [File] = []
        var inFiles = false
        var notes: [String] = []
        var inNotes = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inNotes {
                if line.hasPrefix("  ") || trimmed.isEmpty {
                    notes.append(trimmed)
                    continue
                }
                inNotes = false
            }
            if trimmed.isEmpty { continue }

            if !line.hasPrefix(" ") {
                inFiles = trimmed == "files:"
                if inFiles { continue }
                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                let key = String(trimmed[..<colon])
                let value = unquote(String(trimmed[trimmed.index(after: colon)...]))
                if key == "releaseNotes", value.isEmpty || value == "|" || value.hasPrefix(">") {
                    inNotes = true
                    continue
                }
                top[key] = value
            } else if inFiles {
                if trimmed.hasPrefix("- ") {
                    let entry = String(trimmed.dropFirst(2))
                    if let colon = entry.firstIndex(of: ":"), entry[..<colon] == "url" {
                        files.append(File(name: unquote(String(entry[entry.index(after: colon)...]))))
                    } else {
                        files.append(File(name: ""))
                    }
                } else if let colon = trimmed.firstIndex(of: ":"), !files.isEmpty {
                    let key = String(trimmed[..<colon])
                    let value = unquote(String(trimmed[trimmed.index(after: colon)...]))
                    if key == "url" { files[files.count - 1].name = value }
                    if key == "sha512" { files[files.count - 1].sha512 = value }
                }
            }
        }

        guard let version = top["version"], !version.isEmpty else { return nil }
        files.removeAll { $0.name.isEmpty }

        var defaultFile: File?
        if let path = top["path"], !path.isEmpty {
            defaultFile = files.first { $0.name == path }
                ?? File(name: path, sha512: top["sha512"])
        }
        let releaseDate = top["releaseDate"].flatMap { Self.parseDate($0) }
        let releaseNotes = top["releaseNotes"] ?? (notes.isEmpty ? nil : notes.joined(separator: "\n"))

        return ElectronManifest(
            version: AppVersion(version),
            files: files,
            defaultFile: defaultFile,
            releaseDate: releaseDate,
            releaseNotes: releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The artifact Freshly should install: a zip for this Mac's
    /// architecture, a universal zip, the manifest's default when it is a
    /// zip, any zip at all — in that order. Disk images are skipped; the
    /// zips are what electron-updater itself installs from.
    public func archiveFile(architecture: String = ElectronManifest.currentArchitecture) -> File? {
        let zips = files.filter { $0.name.lowercased().hasSuffix(".zip") }
        if let match = zips.first(where: { $0.name.lowercased().contains(architecture) }) {
            return match
        }
        if let universal = zips.first(where: { $0.name.lowercased().contains("universal") }) {
            return universal
        }
        if let fallback = defaultFile, fallback.name.lowercased().hasSuffix(".zip") {
            return fallback
        }
        return zips.first
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// electron-builder writes fractional seconds (`2026-07-07T23:20:34.590Z`).
    /// `ISO8601DateFormatter` is not `Sendable`, so it is built per parse —
    /// one manifest per app per scan makes that free.
    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}

/// Update source for electron-updater (Squirrel.Mac) apps. Authoritative
/// whenever the scanner found a usable `app-update.yml` — that file *is*
/// the app's installed update channel. The manifest's zip goes through
/// the ordinary install pipeline; its sha512 is verified after download,
/// and Gatekeeper still applies (a checksum proves integrity against the
/// manifest, not the publisher's identity).
public struct ElectronSource: UpdateSource {
    public let id = SourceID.electron

    private let session: URLSession

    public init(session: URLSession = .freshly) {
        self.session = session
    }

    public func applicability(for app: InstalledApp) -> SourceApplicability {
        app.electronManifestURL != nil ? .authoritative : .notApplicable
    }

    public func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        guard let manifestURL = app.electronManifestURL else { return nil }

        let data: Data
        do {
            let (body, response) = try await session.data(from: manifestURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // An auth-gated endpoint is not a channel Freshly can
                // use — an expected shape, not a failure worth a warning
                // badge. LM Studio's R2 bucket answers 400 (missing
                // Authorization), S3 buckets answer 401/403.
                if [400, 401, 403].contains(http.statusCode) {
                    return nil
                }
                throw UpdateError(.sourceHTTPStatus(.electron, status: http.statusCode))
            }
            data = body
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError(.sourceRequestFailed(.electron, detail: error.localizedDescription))
        }

        guard let text = String(data: data, encoding: .utf8),
              let manifest = ElectronManifest.parse(text) else {
            throw UpdateError(.sourceResponseUnreadable(.electron, detail: nil))
        }

        let archive = manifest.archiveFile()
        return ReleaseInfo(
            version: manifest.version,
            sha512: archive?.sha512,
            source: .electron,
            downloadURL: archive.flatMap { Self.artifactURL(for: $0.name, relativeTo: manifestURL) },
            changelog: manifest.releaseNotes,
            publishedAt: manifest.releaseDate
        )
    }

    /// Manifest artifacts are file names relative to the manifest's
    /// location, and routinely contain spaces.
    static func artifactURL(for name: String, relativeTo manifestURL: URL) -> URL? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: encoded, relativeTo: manifestURL)?.absoluteURL
    }
}
