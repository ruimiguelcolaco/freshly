import Foundation
import FreshlyModels
import FreshlySecurity

/// Anything that can produce the stream of installed apps. The engine
/// depends on this instead of the concrete scanner so tests can inject
/// fabricated app lists.
public protocol AppDiscovering: Sendable {
    func apps() -> AsyncStream<InstalledApp>
}

/// Discovers applications installed on this Mac by walking the application
/// directories and inspecting each bundle's `Info.plist` and signature.
///
/// Results stream as they are found — the UI never waits for a full scan.
public struct AppScanner: AppDiscovering, Sendable {
    /// Directories scanned by default.
    public static let defaultLocations: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Applications", directoryHint: .isDirectory),
    ]

    private let locations: [URL]
    /// Bundle inspection reads signing info from disk; a bounded task group
    /// keeps the scan fast without stampeding the disk.
    private let maxConcurrentInspections = 8

    public init(locations: [URL] = AppScanner.defaultLocations) {
        self.locations = locations
    }

    public func apps() -> AsyncStream<InstalledApp> {
        let locations = self.locations
        let width = maxConcurrentInspections
        return AsyncStream { continuation in
            let task = Task(priority: .userInitiated) {
                await withTaskGroup(of: InstalledApp?.self) { group in
                    var pendingURLs = Self.applicationBundles(in: locations)[...]
                    var running = 0

                    func startNext() {
                        while running < width, let url = pendingURLs.popFirst() {
                            group.addTask { Self.inspectBundle(at: url) }
                            running += 1
                        }
                    }

                    startNext()
                    while running > 0, let result = await group.next() {
                        running -= 1
                        if let app = result {
                            continuation.yield(app)
                        }
                        if Task.isCancelled { break }
                        startNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `.app` bundles directly inside the given directories, plus one level
    /// of subdirectories (vendors like Adobe and the Utilities folder nest
    /// their apps one level down). Bundles inside other bundles are ignored.
    static func applicationBundles(in locations: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var seenPaths = Set<String>()

        func appendIfNew(_ url: URL) {
            let path = url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                found.append(url)
            }
        }

        for root in locations {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if child.pathExtension == "app" {
                    appendIfNew(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let nested = (try? fileManager.contentsOfDirectory(
                        at: child,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    for candidate in nested where candidate.pathExtension == "app" {
                        appendIfNew(candidate)
                    }
                }
            }
        }
        return found
    }

    /// Builds an `InstalledApp` from a bundle on disk. Returns `nil` for
    /// bundles without an identifier or version — there is nothing Freshly
    /// could check for them.
    static func inspectBundle(at url: URL) -> InstalledApp? {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = plist as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else {
            return nil
        }

        let shortVersion = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        guard let versionString = shortVersion ?? build else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        var channels: Set<SourceID> = []
        var feedURL: URL?
        if let feedString = info["SUFeedURL"] as? String,
           let url = URL(string: feedString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            feedURL = url
            channels.insert(.sparkle)
        }
        let receiptPath = url.appending(path: "Contents/_MASReceipt/receipt").path
        if FileManager.default.fileExists(atPath: receiptPath) {
            channels.insert(.macAppStore)
        }

        return InstalledApp(
            bundleID: bundleID,
            name: name,
            path: url,
            version: AppVersion(versionString),
            build: build,
            signature: SignatureVerifier().signatureInfo(forAppAt: url),
            installChannels: channels,
            sparkleFeedURL: feedURL,
            sparklePublicEDKey: info["SUPublicEDKey"] as? String
        )
    }

    /// Re-inspects a single bundle — used after an install to refresh the
    /// app's entry without a full rescan.
    public static func inspect(appAt url: URL) -> InstalledApp? {
        inspectBundle(at: url)
    }
}
