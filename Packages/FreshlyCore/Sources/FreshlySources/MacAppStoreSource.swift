import Foundation
import FreshlyModels

/// Checks apps installed from the Mac App Store — detected by their receipt
/// — against Apple's public lookup API.
///
/// Since macOS Tahoe 26.1, third-party apps can no longer install Mac App
/// Store updates directly: this source only *reports* them (`downloadURL`
/// is always `nil`) and the UI hands the user off to the App Store.
///
/// Privacy note: the lookup is a per-app query, but it goes to Apple — the
/// party that already distributes the app and knows the user has it.
public struct MacAppStoreSource: UpdateSource {
    public let id = SourceID.macAppStore

    private let session: URLSession
    private let countryCode: String
    private let currentOSVersion: AppVersion

    public init(
        session: URLSession = .freshly,
        countryCode: String? = nil,
        currentOSVersion: AppVersion = AppVersion.currentMacOSVersion
    ) {
        self.session = session
        // Storefronts differ in which version they serve; ask the user's.
        self.countryCode = countryCode ?? Locale.current.region?.identifier ?? "US"
        self.currentOSVersion = currentOSVersion
    }

    public func applicability(for app: InstalledApp) -> SourceApplicability {
        app.installChannels.contains(.macAppStore) ? .authoritative : .notApplicable
    }

    public func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: app.bundleID),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = components.url else { return nil }

        let data: Data
        do {
            let (body, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw http.statusCode == 403 || http.statusCode == 429
                    ? UpdateError(.sourceRateLimited(.macAppStore))
                    : UpdateError(.sourceHTTPStatus(.macAppStore, status: http.statusCode))
            }
            data = body
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError(.sourceRequestFailed(.macAppStore, detail: error.localizedDescription))
        }

        return try Self.release(fromLookup: data, bundleID: app.bundleID, runningOn: currentOSVersion)
    }

    /// Parses a lookup response into a release. Returns `nil` when the app
    /// is not (or no longer) on the store, or when the store version needs
    /// a newer macOS than this machine runs — an update the user cannot
    /// apply is not an update worth nagging about.
    static func release(
        fromLookup data: Data,
        bundleID: String,
        runningOn osVersion: AppVersion
    ) throws -> ReleaseInfo? {
        let decoded: LookupResponse
        do {
            decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        } catch {
            throw UpdateError(.sourceResponseUnreadable(.macAppStore, detail: nil))
        }

        let macResults = decoded.results.filter { $0.kind == "mac-software" }
        guard let result = macResults.first(where: { $0.bundleId?.lowercased() == bundleID.lowercased() })
            ?? macResults.first else {
            return nil
        }
        guard let version = result.version else { return nil }
        if let minimum = result.minimumOsVersion, AppVersion(minimum) > osVersion {
            return nil
        }

        return ReleaseInfo(
            version: AppVersion(version),
            source: .macAppStore,
            downloadURL: nil,
            releaseNotesURL: result.trackViewUrl,
            changelog: result.releaseNotes,
            publishedAt: result.currentVersionReleaseDate.flatMap {
                ISO8601DateFormatter().date(from: $0)
            },
            minimumOSVersion: result.minimumOsVersion
        )
    }

    struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    struct LookupResult: Decodable {
        let kind: String?
        let bundleId: String?
        let version: String?
        let releaseNotes: String?
        let trackViewUrl: URL?
        let currentVersionReleaseDate: String?
        let minimumOsVersion: String?
    }
}
