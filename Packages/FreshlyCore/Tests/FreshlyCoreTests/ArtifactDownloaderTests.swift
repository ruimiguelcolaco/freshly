import Foundation
import Testing
import FreshlyModels
@testable import FreshlyInstaller

@Suite("ArtifactDownloader")
struct ArtifactDownloaderTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-dl-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Refuses an artifact larger than the cap")
    func refusesOversized() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "big.bin")
        // Larger than the write-flush granularity so the running-total guard
        // also fires even if the file response omits a content length.
        try Data(count: 300 * 1024).write(to: source)

        let downloader = ArtifactDownloader(session: .shared, maxBytes: 50 * 1024)
        await #expect(throws: UpdateError(.downloadTooLarge)) {
            _ = try await downloader.download(from: source, into: dir) { _ in }
        }
    }

    @Test("Downloads an artifact within the cap")
    func acceptsWithinCap() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "small.bin")
        try Data(count: 500).write(to: source)

        let downloader = ArtifactDownloader(session: .shared, maxBytes: 4096)
        let destination = try await downloader.download(from: source, into: dir) { _ in }
        #expect(try Data(contentsOf: destination).count == 500)
    }
}
