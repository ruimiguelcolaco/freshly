import Foundation
import FreshlyModels

/// Persists the update history as a JSON file next to the scan cache,
/// newest first. Installs are rare events, so each append rewrites the
/// whole file — simplicity over throughput, same trade-off as `ScanCache`.
public struct UpdateHistory: Sendable {
    private let fileURL: URL
    private let limit: Int

    /// `limit` caps the file so years of use cannot grow it unbounded;
    /// the oldest records fall off first.
    public init(directory: URL, limit: Int = 500) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "update-history.json")
        self.limit = limit
    }

    public func load() -> [UpdateRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([UpdateRecord].self, from: data) else {
            return []
        }
        return records
    }

    /// Returns the updated history, newest first.
    @discardableResult
    public func append(_ record: UpdateRecord) -> [UpdateRecord] {
        var records = load()
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        save(records)
        return records
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ records: [UpdateRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
