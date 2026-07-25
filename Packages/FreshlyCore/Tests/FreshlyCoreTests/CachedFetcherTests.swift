import Foundation
import Testing
@testable import FreshlySources

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "cached-fetcher.test"
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

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("CachedFetcher", .serialized)
struct CachedFetcherTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "freshly-cached-fetcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("A 304 sends the cached ETag and returns the cached value")
    func conditionalRequest() async throws {
        let directory = try makeDirectory()
        defer {
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try Data("cached".utf8).write(to: directory.appending(path: "sample.json"))
        try #""old-etag""#.write(
            to: directory.appending(path: "sample.etag"),
            atomically: true,
            encoding: .utf8
        )

        let receivedETag = LockedValue<String?>(nil)
        StubURLProtocol.handler = { request in
            receivedETag.set(request.value(forHTTPHeaderField: "If-None-Match"))
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 304,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        let fetcher = CachedFetcher(session: makeSession(), cacheDirectory: directory)
        let value = try await fetcher.fetch(
            URLRequest(url: URL(string: "https://cached-fetcher.test/value")!),
            cacheKey: "sample"
        ) { String(decoding: $0.data, as: UTF8.self) }

        #expect(value == "cached")
        #expect(receivedETag.get() == #""old-etag""#)
    }

    @Test("Malformed network data cannot replace the last good cache")
    func invalidResponseKeepsCache() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let published = directory.appending(path: "published.json")
        let cacheDirectory = directory.appending(path: "cache", directoryHint: .isDirectory)
        try Data("valid".utf8).write(to: published)

        let fetcher = CachedFetcher(session: .shared, cacheDirectory: cacheDirectory)
        let decode: @Sendable (CachedResponse) async throws -> String = { response in
            let value = String(decoding: response.data, as: UTF8.self)
            guard value == "valid" else { throw CachedFetchError.cacheUnavailable }
            return value
        }
        _ = try await fetcher.fetch(URLRequest(url: published), cacheKey: "sample", transform: decode)
        try Data("invalid".utf8).write(to: published)

        let value = try await fetcher.fetch(
            URLRequest(url: published),
            cacheKey: "sample",
            transform: decode
        )
        #expect(value == "valid")
        #expect(try String(contentsOf: cacheDirectory.appending(path: "sample.json"), encoding: .utf8) == "valid")
    }

    @Test("A successful response without an ETag clears the stale validator")
    func missingETagClearsStaleValue() async throws {
        let directory = try makeDirectory()
        defer {
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try Data("old".utf8).write(to: directory.appending(path: "sample.json"))
        try "stale".write(
            to: directory.appending(path: "sample.etag"),
            atomically: true,
            encoding: .utf8
        )
        StubURLProtocol.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("new".utf8))
        }

        let fetcher = CachedFetcher(session: makeSession(), cacheDirectory: directory)
        let value = try await fetcher.fetch(
            URLRequest(url: URL(string: "https://cached-fetcher.test/value")!),
            cacheKey: "sample"
        ) { String(decoding: $0.data, as: UTF8.self) }

        #expect(value == "new")
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "sample.etag").path))
    }

    @Test("The cache directory is private")
    func privateDirectory() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let published = root.appending(path: "published.json")
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        try Data("value".utf8).write(to: published)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        let fetcher = CachedFetcher(session: .shared, cacheDirectory: cacheDirectory)
        _ = try await fetcher.fetch(URLRequest(url: published), cacheKey: "sample") { $0.data }

        let attributes = try FileManager.default.attributesOfItem(atPath: cacheDirectory.path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
    }
}
