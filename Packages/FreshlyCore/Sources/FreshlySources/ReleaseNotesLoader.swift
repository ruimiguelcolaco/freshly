import Foundation
import FreshlyModels

/// Release notes ready for inline display, tagged with the markup the
/// source uses so the UI knows how to render them.
public enum ReleaseNotes: Sendable, Hashable {
    case html(String)
    case markdown(String)
    case plainText(String)
}

/// Resolves the notes to show for a release before the user updates:
/// notes embedded in the source's response when present, the Sparkle
/// `releaseNotesLink` document (fetched on demand) otherwise. Returns
/// `nil` when the source published nothing inline-worthy — the UI then
/// falls back to the release's web page.
public struct ReleaseNotesLoader: Sendable {
    private let session: URLSession

    public init(session: URLSession = .freshly) {
        self.session = session
    }

    public func load(for release: ReleaseInfo) async throws -> ReleaseNotes? {
        if let embedded = Self.embeddedNotes(of: release) {
            return embedded
        }
        guard release.source == .sparkle, let url = release.embeddedNotesURL else {
            return nil
        }
        return try await fetchDocument(at: SparkleSource.enforcingHTTPS(url))
    }

    /// Notes carried in the source's own metadata: appcast `<description>`
    /// is HTML, a GitHub release body is Markdown, the App Store's release
    /// notes are plain text.
    static func embeddedNotes(of release: ReleaseInfo) -> ReleaseNotes? {
        guard let changelog = release.changelog?
            .trimmingCharacters(in: .whitespacesAndNewlines), !changelog.isEmpty else {
            return nil
        }
        return switch release.source {
        case .sparkle: .html(changelog)
        // electron-updater manifests carry the release body, which is
        // Markdown when it comes from GitHub and harmless as it otherwise.
        case .github, .electron: .markdown(changelog)
        case .macAppStore, .homebrew: .plainText(changelog)
        }
    }

    /// Strips the tags and CSS constructs that would make AppKit's HTML
    /// importer fetch a remote resource — a network beacon that would defeat
    /// Freshly's no-server privacy invariant — and bounds the size so a huge
    /// feed document can't hitch the main thread. Not a general-purpose
    /// sanitizer: it removes known resource-reference vectors, it does not
    /// validate the whole document.
    public static func sanitizedNotesHTML(_ html: String) -> String {
        let maxLength = 200_000 // characters; far above any real changelog
        var s = html.count > maxLength ? String(html.prefix(maxLength)) : html
        let patterns = [
            "</?(img|picture|script|iframe|video|audio|source|object|embed|style|link|base)[^>]*>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "@import[^;]*;?",
            "url\\s*\\([^)]*\\)",
            "\\s(style|background|src|href|srcset)\\s*=\\s*\"[^\"]*\"",
            "\\s(style|background|src|href|srcset)\\s*=\\s*'[^']*'",
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(
                of: pattern, with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return s
    }

    private func fetchDocument(at url: URL) async throws -> ReleaseNotes {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw UpdateError(.sourceRequestFailed(.sparkle, detail: error.localizedDescription))
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError(.sourceHTTPStatus(.sparkle, status: http.statusCode))
        }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw UpdateError(.sourceResponseUnreadable(.sparkle, detail: nil))
        }
        return .html(text)
    }
}
