import Foundation
import FreshlyModels

/// Persists the last completed scan so the app opens instantly with the
/// previous state (and the menu bar badge is right from the first frame)
/// while a fresh scan runs underneath.
public struct ScanCache: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "last-scan.json")
    }

    public func load() -> [AppUpdateStatus] {
        guard let data = try? Data(contentsOf: fileURL),
              let statuses = try? JSONDecoder().decode([AppUpdateStatus].self, from: data) else {
            return []
        }
        return statuses
    }

    /// Transient states are not worth reopening with; only settled ones
    /// are written.
    public func save(_ statuses: some Collection<AppUpdateStatus>) {
        let settled = statuses.filter { $0.state != .checking }
        guard let data = try? JSONEncoder().encode(Array(settled)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
