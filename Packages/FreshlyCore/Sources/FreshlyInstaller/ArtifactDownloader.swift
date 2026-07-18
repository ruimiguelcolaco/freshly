import Foundation
import FreshlyModels

/// Streams a release artifact to disk, reporting download progress.
/// Returns the written file's URL — the name comes from the response
/// (honoring `Content-Disposition` and redirects), not the request URL,
/// because download endpoints like `…/darwin-arm64/stable` carry no
/// useful extension.
struct ArtifactDownloader: Sendable {
    let session: URLSession
    /// Upper bound on a single artifact, guarding against a compromised or
    /// broken feed streaming unbounded data and exhausting the disk before
    /// the post-download verification ever runs. No legitimate app-update
    /// download approaches 4 GB; a runaway is refused instead of written out.
    var maxBytes: Int64 = 4 * 1024 * 1024 * 1024

    init(session: URLSession, maxBytes: Int64 = 4 * 1024 * 1024 * 1024) {
        self.session = session
        self.maxBytes = maxBytes
    }

    func download(
        from url: URL,
        into directory: URL,
        progress: @Sendable (Double?) -> Void
    ) async throws -> URL {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(from: url)
        } catch {
            throw UpdateError(.downloadFailed(detail: error.localizedDescription))
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError(.downloadHTTPStatus(status: http.statusCode))
        }
        // Reject an honestly-declared oversize before writing a single byte.
        if response.expectedContentLength > maxBytes {
            throw UpdateError(.downloadTooLarge)
        }

        let name = (response.suggestedFilename ?? "update")
            .replacingOccurrences(of: "/", with: "_")
        let destination = directory.appending(path: name.isEmpty ? "update" : name)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            throw UpdateError(.downloadNotWritable)
        }
        defer { try? handle.close() }

        let expected = response.expectedContentLength // -1 when unknown
        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 256 * 1024 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    // Catches a server that under-declares (or omits) its
                    // length and then streams past the cap.
                    if received > maxBytes {
                        throw UpdateError(.downloadTooLarge)
                    }
                    progress(expected > 0 ? Double(received) / Double(expected) : nil)
                    try Task.checkCancellation()
                }
            }
        } catch is CancellationError {
            throw UpdateError(.downloadCancelled)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError(.downloadFailed(detail: error.localizedDescription))
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        progress(expected > 0 ? 1.0 : nil)
        return destination
    }
}
