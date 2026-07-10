import Foundation
import FreshlyModels

/// Checks apps whose updates are published as GitHub Releases. Only apps
/// mapped to a repository by an app definition are checked — there is no
/// reliable way to guess a repo from a bundle, and guessing wrong means
/// nagging the user about someone else's software.
///
/// Always a candidate, never authoritative: a GitHub repo is where releases
/// live, not proof of how the app was installed.
///
/// Network behavior: one `releases/latest` request per defined app per
/// scan, with ETag conditional requests cached on disk — 304 responses do
/// not count against GitHub's rate limit (60/hour unauthenticated). An
/// optional token raises the limit for power users.
public struct GitHubSource: UpdateSource {
    public let id = SourceID.github

    private let repos: [String: String]
    private let session: URLSession
    private let token: String?
    private let cacheDirectory: URL

    public init(
        repos: [String: String],
        session: URLSession = .freshly,
        token: String? = nil,
        cacheDirectory: URL? = nil
    ) {
        self.repos = repos
        self.session = session
        self.token = token
        self.cacheDirectory = cacheDirectory
            ?? URL.applicationSupportDirectory.appending(path: "Freshly/cache", directoryHint: .isDirectory)
    }

    public func applicability(for app: InstalledApp) -> SourceApplicability {
        repos[app.bundleID] != nil ? .candidate : .notApplicable
    }

    public func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        guard let repo = repos[app.bundleID],
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }

        let safeName = repo.replacingOccurrences(of: "/", with: "_")
        let cacheFile = cacheDirectory.appending(path: "github-\(safeName).json")
        let etagFile = cacheDirectory.appending(path: "github-\(safeName).etag")

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if FileManager.default.fileExists(atPath: cacheFile.path),
           let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            switch http?.statusCode {
            case 304:
                guard let cached = try? Data(contentsOf: cacheFile) else { return nil }
                data = cached
            case 403, 429:
                throw UpdateError(
                    code: .rateLimited,
                    message: "GitHub rate limit reached — try again later, or add a token"
                )
            case .some(200..<300):
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try? body.write(to: cacheFile, options: .atomic)
                if let etag = http?.value(forHTTPHeaderField: "ETag") {
                    try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
                }
                data = body
            default:
                throw UpdateError(code: .network, message: "GitHub returned HTTP \(http?.statusCode ?? -1) for \(repo)")
            }
        } catch let error as UpdateError {
            throw error
        } catch {
            // Offline: a cached release beats none.
            if let cached = try? Data(contentsOf: cacheFile) {
                data = cached
            } else {
                throw UpdateError(code: .network, message: "GitHub request failed: \(error.localizedDescription)")
            }
        }

        return try Self.release(from: data)
    }

    static func release(from data: Data) throws -> ReleaseInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release: Release
        do {
            release = try decoder.decode(Release.self, from: data)
        } catch {
            throw UpdateError(code: .parsing, message: "Could not parse the GitHub release")
        }
        // `releases/latest` already excludes drafts and prereleases; keep
        // the guard for cached or hand-fed data.
        guard release.draft != true, release.prerelease != true else { return nil }
        guard let tag = release.tagName, !tag.isEmpty else { return nil }

        var versionString = tag
        if versionString.lowercased().hasPrefix("v") {
            versionString = String(versionString.dropFirst())
        }

        return ReleaseInfo(
            version: AppVersion(versionString),
            source: .github,
            downloadURL: pickAsset(from: release.assets ?? [])?.browserDownloadUrl,
            releaseNotesURL: release.htmlUrl,
            changelog: release.body,
            publishedAt: release.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    /// The asset that looks most like this Mac's app archive. Returns `nil`
    /// when nothing qualifies — the release is then reported without a
    /// direct download and the UI links to the release page instead.
    static func pickAsset(from assets: [Asset]) -> Asset? {
        let archiveSuffixes = [".zip", ".dmg", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2"]
        let excluded = [
            "linux", "windows", "win32", "win64", ".exe", ".deb", ".rpm",
            ".appimage", "dsym", "symbols", "checksums", "sha256", ".sig",
            ".asc", "source", "src",
        ]

        let scored = assets.compactMap { asset -> (Asset, Int)? in
            let name = asset.name?.lowercased() ?? ""
            guard archiveSuffixes.contains(where: name.hasSuffix) else { return nil }
            guard !excluded.contains(where: name.contains) else { return nil }
            var score = 0
            if name.contains("darwin") || name.contains("mac") || name.contains("osx") { score += 3 }
            if name.contains("universal") { score += 2 }
            #if arch(arm64)
            if name.contains("arm64") || name.contains("aarch64") { score += 2 }
            if name.contains("x86_64") || name.contains("x64") || name.contains("intel") || name.contains("amd64") { score -= 2 }
            #else
            if name.contains("x86_64") || name.contains("x64") || name.contains("intel") || name.contains("amd64") { score += 2 }
            if name.contains("arm64") || name.contains("aarch64") { score -= 2 }
            #endif
            return (asset, score)
        }
        return scored.max { $0.1 < $1.1 }?.0
    }

    struct Release: Decodable {
        let tagName: String?
        let htmlUrl: URL?
        let body: String?
        let publishedAt: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    struct Asset: Decodable {
        let name: String?
        let browserDownloadUrl: URL?
        let contentType: String?
    }
}
