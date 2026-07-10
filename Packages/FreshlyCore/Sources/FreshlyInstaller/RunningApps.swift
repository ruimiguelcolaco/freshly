import AppKit
import Foundation
import FreshlyModels

/// Detects, quits, and relaunches running instances of an app being updated.
enum RunningApps {
    @MainActor
    static func instances(of app: InstalledApp) -> [NSRunningApplication] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: app.bundleID)
            .filter { $0.bundleURL?.standardizedFileURL == app.path.standardizedFileURL }
    }

    /// Returns whether the app was running (and has now quit). Throws when
    /// the app is running and quitting was not allowed, or when it refuses
    /// to quit — the update must not touch a running bundle.
    static func quitIfNeeded(_ app: InstalledApp, allowed: Bool) async throws -> Bool {
        guard await !instances(of: app).isEmpty else { return false }
        guard allowed else {
            throw UpdateError(code: .appRunning, message: "\(app.name) is running. Quit it to update.")
        }

        await MainActor.run {
            for instance in instances(of: app) {
                instance.terminate()
            }
        }
        for _ in 0..<40 { // up to 10 seconds
            if await instances(of: app).isEmpty { return true }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw UpdateError(code: .appRunning, message: "\(app.name) did not quit. Close it and try again.")
    }

    static func launch(appAt url: URL) async {
        _ = try? await NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

/// Removes `com.apple.quarantine` from everything in the verified bundle so
/// the updated app launches without a stale Gatekeeper prompt — the same
/// thing Sparkle does after its own verification.
enum Quarantine {
    static func removeRecursively(at url: URL) {
        var paths = [url.path]
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            while let relative = enumerator.nextObject() as? String {
                paths.append(url.path + "/" + relative)
            }
        }
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
}
