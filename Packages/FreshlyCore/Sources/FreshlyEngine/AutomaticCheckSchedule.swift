import Foundation
import FreshlyModels

public enum AutomaticCheckAction: Equatable, Sendable {
    case disabled
    case wait(TimeInterval)
    case checkNow
    case retryAfter(TimeInterval)

    public func date(relativeTo now: Date) -> Date? {
        switch self {
        case .disabled:
            nil
        case .checkNow:
            now
        case .wait(let delay), .retryAfter(let delay):
            now.addingTimeInterval(delay)
        }
    }
}

public enum AutomaticCheckSchedule {
    public static let busyRetryInterval: TimeInterval = 300
    public static let maximumFailedScanRetryInterval: TimeInterval = 6 * 3600

    public static func failedScanRetryInterval(attempt: Int) -> TimeInterval {
        let boundedAttempt = min(max(0, attempt), 4)
        return min(
            busyRetryInterval * pow(3, Double(boundedAttempt)),
            maximumFailedScanRetryInterval
        )
    }

    public static func nextAction(
        intervalHours: Int,
        lastCheckedAt: Date?,
        now: Date,
        isBusy: Bool,
        retryAt: Date? = nil
    ) -> AutomaticCheckAction {
        guard intervalHours > 0 else {
            return .disabled
        }

        if let retryAt {
            let remaining = max(0, retryAt.timeIntervalSince(now))
            if remaining > 0 {
                return .retryAfter(remaining)
            }
            return isBusy ? .retryAfter(busyRetryInterval) : .checkNow
        }

        guard let lastCheckedAt else {
            return isBusy ? .retryAfter(busyRetryInterval) : .checkNow
        }

        let interval = TimeInterval(intervalHours) * 3600
        let dueAt = lastCheckedAt.addingTimeInterval(interval)
        let remaining = min(interval, max(0, dueAt.timeIntervalSince(now)))

        if remaining > 0 {
            return .wait(remaining)
        }
        return isBusy ? .retryAfter(busyRetryInterval) : .checkNow
    }

    public static func shouldRetryAfterFailedScan(_ states: [UpdateState]) -> Bool {
        var foundRetriableFailure = false

        for state in states {
            switch state {
            case .upToDate, .outdated, .skipped:
                return false
            case .failed(let error):
                guard error.code == .network || error.code == .rateLimited else {
                    return false
                }
                foundRetriableFailure = true
            case .checking, .unsupported:
                continue
            }
        }

        return foundRetriableFailure
    }
}
