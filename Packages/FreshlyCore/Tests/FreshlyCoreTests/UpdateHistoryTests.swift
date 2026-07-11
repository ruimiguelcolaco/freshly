import Foundation
import Testing
import FreshlyModels
@testable import FreshlyEngine

@Suite("UpdateHistory")
struct UpdateHistoryTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "freshly-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func record(
        _ name: String,
        to version: AppVersion = "2.0",
        outcome: UpdateRecord.Outcome = .installed
    ) -> UpdateRecord {
        UpdateRecord(
            bundleID: "com.example.\(name)",
            appName: name,
            fromVersion: "1.0",
            toVersion: version,
            source: .sparkle,
            outcome: outcome
        )
    }

    @Test("Records roundtrip, newest first")
    func roundtrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistory(directory: directory)

        let first = record("A")
        let second = record("B", outcome: .failed(UpdateError(.gatekeeperRejected)))
        history.append(first)
        history.append(second)

        #expect(history.load() == [second, first])
    }

    @Test("The history is capped; the oldest records fall off")
    func capped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistory(directory: directory, limit: 3)

        for index in 1...5 {
            history.append(record("App\(index)"))
        }

        let names = history.load().map(\.appName)
        #expect(names == ["App5", "App4", "App3"])
    }

    @Test("Clearing removes everything")
    func clears() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistory(directory: directory)

        history.append(record("A"))
        history.clear()
        #expect(history.load().isEmpty)
    }

    @Test("A missing or corrupt file loads as an empty history")
    func corruptFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = UpdateHistory(directory: directory)

        #expect(history.load().isEmpty)
        try Data("not json".utf8).write(to: directory.appending(path: "update-history.json"))
        #expect(history.load().isEmpty)
    }
}
