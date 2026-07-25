import Foundation
import FreshlyModels

/// Stable, machine-readable summary of one headless update check.
public struct UpdateCheckReport: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public struct AvailableUpdate: Sendable, Codable, Equatable {
        public let bundleID: String
        public let name: String
        public let path: String
        public let installedVersion: String
        public let availableVersion: String
        public let source: SourceID
    }

    public struct Failure: Sendable, Codable, Equatable {
        public let bundleID: String
        public let name: String
        public let path: String
        public let code: UpdateError.Code
    }

    public let schemaVersion: Int
    public let checkedAt: Date
    public let checkedApps: Int
    public let unsupportedApps: Int
    public let updates: [AvailableUpdate]
    public let failures: [Failure]

    public init(statuses: [AppUpdateStatus], checkedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.checkedAt = checkedAt

        var checkedApps = 0
        var unsupportedApps = 0
        var updates: [AvailableUpdate] = []
        var failures: [Failure] = []

        for status in statuses {
            switch status.state {
            case .checking:
                continue
            case .outdated(let best, _):
                checkedApps += 1
                updates.append(AvailableUpdate(
                    bundleID: status.app.bundleID,
                    name: status.app.name,
                    path: status.app.path.path,
                    installedVersion: status.app.version.rawValue,
                    availableVersion: best.version.rawValue,
                    source: best.source
                ))
            case .failed(let error):
                checkedApps += 1
                failures.append(Failure(
                    bundleID: status.app.bundleID,
                    name: status.app.name,
                    path: status.app.path.path,
                    code: error.code
                ))
            case .unsupported:
                checkedApps += 1
                unsupportedApps += 1
            case .upToDate, .skipped:
                checkedApps += 1
            }
        }

        func ordered(_ lhs: (bundleID: String, path: String), _ rhs: (bundleID: String, path: String)) -> Bool {
            lhs.bundleID == rhs.bundleID ? lhs.path < rhs.path : lhs.bundleID < rhs.bundleID
        }
        updates.sort {
            ordered(($0.bundleID, $0.path), ($1.bundleID, $1.path))
        }
        failures.sort {
            ordered(($0.bundleID, $0.path), ($1.bundleID, $1.path))
        }

        self.checkedApps = checkedApps
        self.unsupportedApps = unsupportedApps
        self.updates = updates
        self.failures = failures
    }
}
