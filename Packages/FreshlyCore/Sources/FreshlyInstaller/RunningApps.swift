import AppKit
import Foundation
import FreshlyModels

/// Detects, quits, and relaunches running instances of an app being updated.
public enum RunningApps {
    @MainActor
    public static func instances(of app: InstalledApp) -> [NSRunningApplication] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: app.bundleID)
            .filter { $0.bundleURL?.standardizedFileURL == app.path.standardizedFileURL }
    }

    /// Returns whether the app was running (and has now quit). Throws when
    /// the app is running and quitting was not allowed, or when it survives
    /// even a forced quit — the update must not touch a running bundle.
    ///
    /// The app is asked to quit gracefully first, so a document app can save
    /// or prompt. Persistent utilities (menu-bar apps like Raycast) routinely
    /// ignore that request and stay up, which used to strand the update; so
    /// if the app is still running after the grace period, it is
    /// force-quit — the user already consented to the update, and updating a
    /// running app is the whole point.
    public static func quitIfNeeded(_ app: InstalledApp, allowed: Bool) async throws -> Bool {
        guard await !instances(of: app).isEmpty else { return false }
        guard allowed else {
            throw UpdateError(.appRunning(appName: app.name))
        }

        // Ask nicely — lets the app save state / close cleanly.
        await terminate(app, force: false)
        if await waitUntilGone(app, attempts: 32) { return true } // ~8s

        // Ignored the request: force it. The user asked for the update.
        await terminate(app, force: true)
        if await waitUntilGone(app, attempts: 20) { return true } // ~5s

        throw UpdateError(.appDidNotQuit(appName: app.name))
    }

    @MainActor
    private static func terminate(_ app: InstalledApp, force: Bool) {
        for instance in instances(of: app) {
            if force {
                instance.forceTerminate()
            } else {
                instance.terminate()
            }
        }
    }

    private static func waitUntilGone(_ app: InstalledApp, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if await instances(of: app).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return await instances(of: app).isEmpty
    }

    public static func launch(appAt url: URL) async {
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
