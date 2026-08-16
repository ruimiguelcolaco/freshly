import Foundation
import Observation
import FreshlyModels

/// Persists "skip this version" choices as JSON in Application Support,
/// keyed by bundle ID. A skip applies to one version: when something newer
/// appears, the app shows up as outdated again.
@Observable
@MainActor
final class SkipStore {
    private(set) var skips: [String: AppVersion] = [:]
    private let fileURL: URL

    init(
        directory: URL = URL.applicationSupportDirectory
            .appending(path: "Freshly", directoryHint: .isDirectory)
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "skips.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: AppVersion].self, from: data) {
            skips = decoded
        }
    }

    func skippedVersion(for bundleID: String) -> AppVersion? {
        skips[bundleID]
    }

    func skip(version: AppVersion, forBundleID bundleID: String) {
        skips[bundleID] = version
        save()
    }

    func unskip(bundleID: String) {
        skips.removeValue(forKey: bundleID)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(skips) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
