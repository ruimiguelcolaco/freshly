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
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let delegate = ProgressDelegate(maxBytes: maxBytes, progress: progress)
        let temporary: URL
        let response: URLResponse

        do {
            (temporary, response) = try await session.download(
                for: URLRequest(url: url),
                delegate: delegate
            )
        } catch {
            if let failure = delegate.failure {
                throw failure
            }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw UpdateError(.downloadCancelled)
            }
            throw UpdateError(.downloadFailed(detail: error.localizedDescription))
        }

        guard !Task.isCancelled else {
            throw UpdateError(.downloadCancelled)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError(.downloadHTTPStatus(status: http.statusCode))
        }

        let received = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) ?? 0
        if response.expectedContentLength > maxBytes || received > maxBytes {
            throw UpdateError(.downloadTooLarge)
        }

        let name = (response.suggestedFilename ?? "update")
            .replacing("/", with: "_")
        let destination = directory.appending(path: name.isEmpty ? "update" : name)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            throw UpdateError(.downloadNotWritable)
        }

        progress(response.expectedContentLength > 0 ? 1.0 : nil)
        return destination
    }

    /// `URLSessionDownloadTask` streams to a temporary file in native-sized
    /// chunks. This avoids iterating a large artifact one `UInt8` at a time
    /// while retaining progress, cancellation, HTTP and size validation.
    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let maxBytes: Int64
        private let progress: @Sendable (Double?) -> Void
        private let lock = NSLock()
        private var storedFailure: UpdateError?

        init(maxBytes: Int64, progress: @escaping @Sendable (Double?) -> Void) {
            self.maxBytes = maxBytes
            self.progress = progress
        }

        var failure: UpdateError? {
            lock.withLock { storedFailure }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                lock.withLock {
                    storedFailure = UpdateError(.downloadHTTPStatus(status: http.statusCode))
                }
                downloadTask.cancel()
                return
            }
            if downloadTask.response?.expectedContentLength ?? -1 > maxBytes
                || totalBytesWritten > maxBytes {
                lock.withLock {
                    storedFailure = UpdateError(.downloadTooLarge)
                }
                downloadTask.cancel()
                return
            }

            progress(
                totalBytesExpectedToWrite > 0
                    ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                    : nil
            )
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {}
    }
}
