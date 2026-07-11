import Foundation

/// One update attempt the user made through Freshly: what was updated,
/// when, through which channel, and how it ended. The local history is a
/// list of these — nothing leaves the machine.
public struct UpdateRecord: Sendable, Hashable, Codable, Identifiable {
    public enum Outcome: Sendable, Hashable, Codable {
        case installed
        case failed(UpdateError)
    }

    public var id: UUID
    public var date: Date
    public var bundleID: String
    public var appName: String
    public var fromVersion: AppVersion
    public var toVersion: AppVersion
    public var source: SourceID
    public var outcome: Outcome

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        bundleID: String,
        appName: String,
        fromVersion: AppVersion,
        toVersion: AppVersion,
        source: SourceID,
        outcome: Outcome
    ) {
        self.id = id
        self.date = date
        self.bundleID = bundleID
        self.appName = appName
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.source = source
        self.outcome = outcome
    }
}
