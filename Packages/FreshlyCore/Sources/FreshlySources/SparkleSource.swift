import Foundation
import FreshlyModels

/// Checks apps that publish a Sparkle appcast — the most common update
/// mechanism for third-party Mac apps. Authoritative whenever the scanner
/// found an `SUFeedURL` in the app's `Info.plist`.
public struct SparkleSource: UpdateSource {
    public let id = SourceID.sparkle

    private let session: URLSession
    private let currentOSVersion: AppVersion

    public init(
        session: URLSession = .freshly,
        currentOSVersion: AppVersion = AppVersion.currentMacOSVersion
    ) {
        self.session = session
        self.currentOSVersion = currentOSVersion
    }

    public func applicability(for app: InstalledApp) -> SourceApplicability {
        app.sparkleFeedURL != nil ? .authoritative : .notApplicable
    }

    public func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        guard let declaredURL = app.sparkleFeedURL else { return nil }
        let feedURL = Self.enforcingHTTPS(declaredURL)

        let data: Data
        do {
            let (body, response) = try await session.data(from: feedURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw UpdateError(.sourceHTTPStatus(.sparkle, status: http.statusCode))
            }
            data = body
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError(.sourceRequestFailed(.sparkle, detail: error.localizedDescription))
        }

        let items = try AppcastParser().parse(data)
        guard let latest = Self.pickLatest(from: items, runningOn: currentOSVersion) else {
            return nil
        }

        return ReleaseInfo(
            version: latest.displayVersion!,
            build: latest.version,
            edSignature: latest.edSignature,
            source: .sparkle,
            downloadURL: latest.enclosureURL,
            releaseNotesURL: latest.releaseNotesURL ?? latest.link,
            embeddedNotesURL: latest.releaseNotesURL,
            changelog: latest.descriptionHTML,
            publishedAt: latest.pubDate,
            minimumOSVersion: latest.minimumSystemVersion
        )
    }

    /// The newest item this Mac can actually run: default channel only
    /// (no betas), minimum system version satisfied, highest version wins.
    static func pickLatest(from items: [AppcastItem], runningOn osVersion: AppVersion) -> AppcastItem? {
        items
            .filter { item in
                guard item.channel == nil, item.displayVersion != nil else { return false }
                if let minimum = item.minimumSystemVersion, AppVersion(minimum) > osVersion {
                    return false
                }
                return true
            }
            .max { $0.displayVersion! < $1.displayVersion! }
    }

    /// Old apps still declare plain-http feeds; fetch them over TLS.
    static func enforcingHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }
}

extension AppVersion {
    /// The running macOS version, e.g. `26.1.0`.
    public static var currentMacOSVersion: AppVersion {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return AppVersion("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }
}

extension URLSession {
    /// The session all sources share: ephemeral (nothing persisted),
    /// short timeouts, honest User-Agent.
    public static let freshly: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Freshly (https://github.com/ruimiguelcolaco/freshly)"]
        return URLSession(configuration: configuration)
    }()
}
