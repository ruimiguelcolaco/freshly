import Foundation

/// The bytes selected by `CachedFetcher`, plus enough cache metadata for
/// callers that memoize their decoded representation.
public struct CachedResponse: Sendable {
    public let data: Data
    public let etag: String?
    public let isCached: Bool
}

/// Failures that remain after the fetcher has tried its disk fallback.
public enum CachedFetchError: Error, Sendable {
    case httpStatus(Int)
    case cacheUnavailable
    case requestFailed(String)
}

/// Shared conditional-GET and disk-cache policy for network sources.
///
/// A successful response is decoded before it replaces the last good cache,
/// so malformed server data cannot poison an offline fallback. Transport
/// failures use the cache automatically; callers choose whether HTTP errors
/// should do the same.
public struct CachedFetcher: Sendable {
    private let session: URLSession
    private let cacheDirectory: URL

    public init(session: URLSession = .freshly, cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory
            ?? URL.applicationSupportDirectory.appending(path: "Freshly/cache", directoryHint: .isDirectory)
    }

    public func cachedValue<Value: Sendable>(
        for cacheKey: String,
        transform: @Sendable (CachedResponse) throws -> Value
    ) throws -> Value? {
        prepareCacheDirectory()
        let files = cacheFiles(for: cacheKey)
        guard let data = try? Data(contentsOf: files.body) else { return nil }
        return try transform(CachedResponse(
            data: data,
            etag: readETag(from: files.etag),
            isCached: true
        ))
    }

    public func fetch<Value: Sendable>(
        _ originalRequest: URLRequest,
        cacheKey: String,
        fallbackOnHTTPError: Bool = false,
        transform: @Sendable (CachedResponse) async throws -> Value
    ) async throws -> Value {
        prepareCacheDirectory()
        let files = cacheFiles(for: cacheKey)
        let cachedData = try? Data(contentsOf: files.body)
        let cachedETag = cachedData == nil ? nil : readETag(from: files.etag)
        let cachedResponse = cachedData.map {
            CachedResponse(data: $0, etag: cachedETag, isCached: true)
        }

        var request = originalRequest
        if let cachedETag, !cachedETag.isEmpty {
            request.setValue(cachedETag, forHTTPHeaderField: "If-None-Match")
        }

        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await session.data(for: request)
        } catch {
            if let cachedResponse {
                return try await transform(cachedResponse)
            }
            throw CachedFetchError.requestFailed(error.localizedDescription)
        }

        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 {
            guard let cachedResponse else {
                throw CachedFetchError.cacheUnavailable
            }
            return try await transform(cachedResponse)
        }
        if let status = http?.statusCode, !(200..<300).contains(status) {
            if fallbackOnHTTPError, let cachedResponse {
                return try await transform(cachedResponse)
            }
            throw CachedFetchError.httpStatus(status)
        }

        let newETag = http?.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let networkResponse = CachedResponse(data: body, etag: newETag, isCached: false)
        let value: Value
        do {
            value = try await transform(networkResponse)
        } catch {
            if let cachedResponse, let cachedValue = try? await transform(cachedResponse) {
                return cachedValue
            }
            throw error
        }

        prepareCacheDirectory()
        try? body.write(to: files.body, options: .atomic)
        if let newETag, !newETag.isEmpty {
            try? newETag.write(to: files.etag, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: files.etag)
        }
        return value
    }

    private func cacheFiles(for cacheKey: String) -> (body: URL, etag: URL) {
        let safeKey = cacheKey.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_"
        }
        let key = String(safeKey)
        return (
            cacheDirectory.appending(path: "\(key).json"),
            cacheDirectory.appending(path: "\(key).etag")
        )
    }

    private func readETag(from file: URL) -> String? {
        try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareCacheDirectory() {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: attributes
        )
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: cacheDirectory.path)
    }
}
