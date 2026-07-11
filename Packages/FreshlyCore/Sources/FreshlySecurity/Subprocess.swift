import Foundation
import FreshlyModels

/// Minimal async wrapper around `Process` for the system tools Freshly
/// shells out to (`spctl`, `ditto`, `hdiutil`, `tar`, `brew`).
public enum Subprocess {
    public struct Output: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Runs the tool and returns its exit status and output. Throws only
    /// when the process cannot be spawned. Pipes are drained concurrently
    /// while the process runs, so chatty tools (like `brew`) cannot
    /// deadlock on a full pipe buffer.
    public static func run(
        _ tool: String,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, override in override }
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (exitCodes, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw UpdateError(.toolNotRunnable(
                tool: URL(fileURLWithPath: tool).lastPathComponent,
                detail: error.localizedDescription
            ))
        }

        async let stdoutData = drain(stdoutPipe.fileHandleForReading)
        async let stderrData = drain(stderrPipe.fileHandleForReading)
        var status: Int32 = -1
        for await code in exitCodes {
            status = code
        }
        return Output(
            status: status,
            stdout: String(decoding: await stdoutData, as: UTF8.self),
            stderr: String(decoding: await stderrData, as: UTF8.self)
        )
    }

    /// Like `run`, but a nonzero exit is an error.
    @discardableResult
    public static func runChecked(
        _ tool: String,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> String {
        let output = try await run(tool, arguments, environment: environment)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError(.toolFailed(
                tool: URL(fileURLWithPath: tool).lastPathComponent,
                status: Int(output.status),
                detail: detail
            ))
        }
        return output.stdout
    }

    private static func drain(_ handle: FileHandle) async -> Data {
        var data = Data()
        do {
            for try await byte in handle.bytes {
                data.append(byte)
            }
        } catch {
            // A broken pipe just ends the stream; partial output is fine.
        }
        return data
    }
}
