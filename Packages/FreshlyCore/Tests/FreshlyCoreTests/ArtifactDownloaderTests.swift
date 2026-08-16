import Foundation
import Testing
import FreshlyModels
@testable import FreshlyInstaller

private final class ArtifactStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "artifact-downloader.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var determinateValues: [Double] = []

    func record(_ value: Double?) {
        guard let value else { return }
        lock.withLock {
            determinateValues.append(value)
        }
    }

    var lastValue: Double? {
        lock.withLock { determinateValues.last }
    }
}

@Suite("ArtifactDownloader", .serialized)
struct ArtifactDownloaderTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-dl-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSourceFile(named name: String, contents: Data, under directory: URL) throws -> URL {
        let sourceDirectory = directory.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appending(path: name)
        try contents.write(to: source)
        return source
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtifactStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("Refuses an artifact larger than the cap")
    func refusesOversized() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A local file response exercises the running-total guard without
        // relying on a server-declared Content-Length.
        let source = try makeSourceFile(
            named: "big.bin",
            contents: Data(count: 300 * 1024),
            under: dir
        )

        let downloader = ArtifactDownloader(session: .shared, maxBytes: 50 * 1024)
        await #expect(throws: UpdateError(.downloadTooLarge)) {
            _ = try await downloader.download(from: source, into: dir) { _ in }
        }
    }

    @Test("Downloads an artifact within the cap")
    func acceptsWithinCap() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let expected = Data((0..<500).map { UInt8($0 % 251) })
        let source = try makeSourceFile(named: "small.bin", contents: expected, under: dir)

        let downloader = ArtifactDownloader(session: .shared, maxBytes: 4096)
        let destination = try await downloader.download(from: source, into: dir) { _ in }
        #expect(destination.lastPathComponent == "small.bin")
        #expect(try Data(contentsOf: destination) == expected)
    }

    @Test("Refuses an unknown-length HTTP download when its running total crosses the cap")
    func refusesUnknownLengthHTTPDownload() async throws {
        let dir = try makeTempDir()
        defer {
            ArtifactStubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let oversized = Data(repeating: 0xA5, count: 128 * 1024)
        ArtifactStubURLProtocol.handler = { request in
            let responseURL = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            #expect(response.expectedContentLength == -1)
            return (response, oversized)
        }
        let url = try #require(URL(string: "https://artifact-downloader.test/stream"))
        let downloader = ArtifactDownloader(session: makeSession(), maxBytes: 32 * 1024)

        await #expect(throws: UpdateError(.downloadTooLarge)) {
            _ = try await downloader.download(from: url, into: dir) { _ in }
        }
    }

    @Test("Maps task cancellation to the structured download error")
    func cancellation() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeSourceFile(
            named: "cancel.bin",
            contents: Data(count: 1024 * 1024),
            under: dir
        )
        let downloader = ArtifactDownloader(session: .shared)
        let task = Task {
            try await downloader.download(from: source, into: dir) { _ in }
        }

        task.cancel()

        await #expect(throws: UpdateError(.downloadCancelled)) {
            _ = try await task.value
        }
    }

    @Test("Preserves response filename and reports determinate progress")
    func responseMetadataAndProgress() async throws {
        let dir = try makeTempDir()
        defer {
            ArtifactStubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let expected = Data(repeating: 0xA5, count: 512 * 1024)
        ArtifactStubURLProtocol.handler = { request in
            let responseURL = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Length": "\(expected.count)",
                    "Content-Disposition": #"attachment; filename="Freshly Test.zip""#,
                ]
            ))
            return (response, expected)
        }
        let url = try #require(URL(string: "https://artifact-downloader.test/release"))
        let recorder = ProgressRecorder()

        let destination = try await ArtifactDownloader(session: makeSession())
            .download(from: url, into: dir) { recorder.record($0) }

        #expect(destination.lastPathComponent == "Freshly Test.zip")
        #expect(try Data(contentsOf: destination) == expected)
        #expect(recorder.lastValue == 1.0)
    }

    @Test("Maps non-success HTTP responses to a structured error")
    func httpError() async throws {
        let dir = try makeTempDir()
        defer {
            ArtifactStubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: dir)
        }
        ArtifactStubURLProtocol.handler = { request in
            let responseURL = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: responseURL,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("unavailable".utf8))
        }
        let url = try #require(URL(string: "https://artifact-downloader.test/release"))
        let downloader = ArtifactDownloader(session: makeSession())

        await #expect(throws: UpdateError(.downloadHTTPStatus(status: 503))) {
            _ = try await downloader.download(from: url, into: dir) { _ in }
        }
    }
}
