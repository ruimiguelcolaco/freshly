import Foundation
import Testing
@testable import FreshlyEngine
import FreshlyModels

@Suite("AutomaticCheckSchedule")
struct AutomaticCheckScheduleTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Manual mode disables automatic checks")
    func manualMode() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 0,
            lastCheckedAt: nil,
            now: now,
            isBusy: false,
            retryAt: now.addingTimeInterval(300)
        )

        #expect(action == .disabled)
    }

    @Test("An app that has never checked starts immediately")
    func firstCheck() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: nil,
            now: now,
            isBusy: false
        )

        #expect(action == .checkNow)
    }

    @Test("A recent check waits only for the interval remainder")
    func intervalRemainder() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: now.addingTimeInterval(-6 * 3600),
            now: now,
            isBusy: false
        )

        #expect(action == .wait(18 * 3600))
    }

    @Test("An overdue check starts immediately")
    func overdueCheck() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: now.addingTimeInterval(-25 * 3600),
            now: now,
            isBusy: false
        )

        #expect(action == .checkNow)
    }

    @Test("A busy app retries shortly when a check is due")
    func busyRetry() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: now.addingTimeInterval(-24 * 3600),
            now: now,
            isBusy: true
        )

        #expect(action == .retryAfter(300))
    }

    @Test("A future timestamp never postpones more than one interval")
    func futureTimestamp() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: now.addingTimeInterval(7 * 24 * 3600),
            now: now,
            isBusy: false
        )

        #expect(action == .wait(24 * 3600))
    }

    @Test("A failed scan retry takes precedence over the normal interval")
    func failedScanRetry() {
        let action = AutomaticCheckSchedule.nextAction(
            intervalHours: 24,
            lastCheckedAt: now,
            now: now,
            isBusy: false,
            retryAt: now.addingTimeInterval(300)
        )

        #expect(action == .retryAfter(300))
    }

    @Test("Repeated failed scans back off and cap at six hours")
    func failedScanBackoff() {
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 0) == 300)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 1) == 900)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 2) == 2700)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 3) == 8100)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 4) == 21_600)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: 100) == 21_600)
        #expect(AutomaticCheckSchedule.failedScanRetryInterval(attempt: -1) == 300)
    }

    @Test("A total network failure retries, but a useful result completes the scan")
    func failedScanClassification() {
        let networkFailure = UpdateState.failed(
            UpdateError(.sourceRequestFailed(.sparkle, detail: "offline"))
        )
        let rateLimit = UpdateState.failed(
            UpdateError(.sourceRateLimited(.github))
        )

        #expect(AutomaticCheckSchedule.shouldRetryAfterFailedScan([
            .unsupported,
            networkFailure,
            rateLimit,
        ]))
        #expect(!AutomaticCheckSchedule.shouldRetryAfterFailedScan([
            .upToDate,
            networkFailure,
        ]))
        #expect(!AutomaticCheckSchedule.shouldRetryAfterFailedScan([
            .failed(UpdateError(.sourceResponseUnreadable(.sparkle, detail: nil))),
        ]))
    }

    @Test("Actions expose their next scheduled date")
    func scheduledDates() {
        #expect(AutomaticCheckAction.disabled.date(relativeTo: now) == nil)
        #expect(AutomaticCheckAction.checkNow.date(relativeTo: now) == now)
        #expect(
            AutomaticCheckAction.wait(3600).date(relativeTo: now)
                == now.addingTimeInterval(3600)
        )
        #expect(
            AutomaticCheckAction.retryAfter(300).date(relativeTo: now)
                == now.addingTimeInterval(300)
        )
    }
}
