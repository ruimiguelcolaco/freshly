import Foundation
import FreshlyModels

/// Persistable recovery state around `AutomaticCheckSchedule`. The app owns
/// sleeping and system events; this value owns retry transitions and backoff.
public struct AutomaticCheckRecovery: Sendable, Equatable {
    public private(set) var retryAt: Date?
    public private(set) var failedScanRetryAttempt: Int

    public init(retryAt: Date? = nil, failedScanRetryAttempt: Int = 0) {
        self.retryAt = retryAt
        self.failedScanRetryAttempt = max(0, failedScanRetryAttempt)
    }

    /// Returns true when the scan produced useful results and may advance the
    /// normal last-checked anchor.
    @discardableResult
    public mutating func recordScan(_ states: [UpdateState], now: Date) -> Bool {
        if AutomaticCheckSchedule.shouldRetryAfterFailedScan(states) {
            scheduleRetry(now: now)
            return false
        }
        clear()
        return true
    }

    public mutating func scheduleRetry(now: Date) {
        let delay = AutomaticCheckSchedule.failedScanRetryInterval(
            attempt: failedScanRetryAttempt
        )
        failedScanRetryAttempt += 1
        retryAt = now.addingTimeInterval(delay)
    }

    /// Pulls an existing retry forward when connectivity returns.
    @discardableResult
    public mutating func restoreConnectivity(now: Date) -> Bool {
        guard retryAt != nil else { return false }
        retryAt = now
        return true
    }

    public mutating func beginScheduledCheck() {
        retryAt = nil
    }

    public mutating func clear() {
        retryAt = nil
        failedScanRetryAttempt = 0
    }
}
