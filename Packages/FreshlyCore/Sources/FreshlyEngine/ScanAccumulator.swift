import Foundation
import FreshlyModels

/// Pure state transition for one streamed scan. It keeps settled cached rows
/// visible while their fresh checking emission arrives, then removes apps the
/// completed scan did not discover.
public struct ScanAccumulator: Sendable {
    public private(set) var statuses: [URL: AppUpdateStatus]
    private var seen: Set<URL> = []

    public init(previous: [URL: AppUpdateStatus]) {
        statuses = previous
    }

    /// Returns whether the visible dictionary changed.
    @discardableResult
    public mutating func receive(_ status: AppUpdateStatus) -> Bool {
        seen.insert(status.id)
        if status.state == .checking, statuses[status.id] != nil {
            return false
        }
        statuses[status.id] = status
        return true
    }

    public mutating func finish() -> [URL: AppUpdateStatus] {
        statuses = statuses.filter { seen.contains($0.key) }
        return statuses
    }
}
