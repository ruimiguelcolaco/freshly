import Foundation
import FreshlyModels

/// Decodes `T` if possible, otherwise `nil` — without throwing, so an
/// array of these skips unreadable elements instead of failing wholesale.
/// A throwing decode inside an unkeyed container does not reliably
/// advance past a bad element, so the wrapper swallows the error itself.
private struct Resilient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Persists the update history as a JSON file next to the scan cache,
/// newest first. Installs are rare events, so each append rewrites the
/// whole file — simplicity over throughput, same trade-off as `ScanCache`.
///
/// Unlike the scan cache, this data cannot be regenerated, so decoding is
/// lenient: the file is a versioned envelope and a single unreadable
/// record is dropped rather than costing the whole history. Old bare-array
/// files (schema-less, pre-envelope) are migrated transparently on read.
public struct UpdateHistory: Sendable {
    private struct Envelope: Codable {
        var schemaVersion: Int
        var records: [UpdateRecord]
    }

    /// Same shape as `Envelope`, but each record decodes leniently so one
    /// bad record doesn't fail the whole array.
    private struct ResilientEnvelope: Decodable {
        var schemaVersion: Int
        var records: [Resilient<UpdateRecord>]
    }

    private static let currentSchemaVersion = 1

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
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        if let envelope = try? JSONDecoder().decode(ResilientEnvelope.self, from: data) {
            return envelope.records.compactMap(\.value)
        }

        // No schemaVersion key — an old bare-array file. Migrate on read;
        // the next append rewrites it as an envelope via save().
        if let bareRecords = try? JSONDecoder().decode([Resilient<UpdateRecord>].self, from: data) {
            return bareRecords.compactMap(\.value)
        }

        return []
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
        let envelope = Envelope(schemaVersion: Self.currentSchemaVersion, records: records)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
