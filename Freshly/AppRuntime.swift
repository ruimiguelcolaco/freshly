import Foundation

/// Runtime defaults for the app process. The hosted unit-test process loads
/// the SwiftUI app before the test bundle, so it must also stay isolated from
/// user storage and system services.
enum AppRuntime {
    static var isTesting: Bool {
        ProcessInfo.processInfo.environment["FRESHLY_TESTING"] == "1"
    }

    static var applicationSupportDirectory: URL {
        if isTesting {
            return FileManager.default.temporaryDirectory.appending(
                path: "Freshly-test-host-\(ProcessInfo.processInfo.processIdentifier)",
                directoryHint: .isDirectory
            )
        }
        return URL.applicationSupportDirectory
            .appending(path: "Freshly", directoryHint: .isDirectory)
    }

    static var userDefaults: UserDefaults {
        guard isTesting else { return .standard }
        return UserDefaults(
            suiteName: "FreshlyTests.Host.\(ProcessInfo.processInfo.processIdentifier)"
        ) ?? .standard
    }
}
