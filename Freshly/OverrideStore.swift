import Foundation
import Observation
import FreshlyModels

/// Persists per-app update-channel overrides as JSON in Application
/// Support, keyed by bundle ID — the user's answer when several sources
/// claim the same app.
@Observable
@MainActor
final class OverrideStore {
    private(set) var overrides: [String: SourceID] = [:]
    private let fileURL: URL

    init(
        directory: URL = URL.applicationSupportDirectory
            .appending(path: "Freshly", directoryHint: .isDirectory)
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "source-overrides.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: SourceID].self, from: data) {
            overrides = decoded
        }
    }

    func preferredSource(for bundleID: String) -> SourceID? {
        overrides[bundleID]
    }

    func setPreferredSource(_ source: SourceID, for bundleID: String) {
        overrides[bundleID] = source
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
