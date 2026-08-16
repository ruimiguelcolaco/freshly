import Foundation
import Testing
import FreshlyEngine
import FreshlyModels

@Suite("App orchestration policies")
struct AppOrchestrationPolicyTests {
    private func status(
        _ name: String,
        state: UpdateState = .checking
    ) -> AppUpdateStatus {
        AppUpdateStatus(
            app: InstalledApp(
                bundleID: "com.example.\(name)",
                name: name,
                path: URL(filePath: "/Applications/\(name).app"),
                version: "1.0"
            ),
            state: state
        )
    }

    private func outdated(
        _ name: String,
        source: SourceID = .sparkle,
        downloadURL: URL? = URL(filePath: "/tmp/update.zip")
    ) -> AppUpdateStatus {
        status(name, state: .outdated(
            best: ReleaseInfo(
                version: "2.0",
                source: source,
                downloadURL: downloadURL,
                releaseNotesURL: URL(string: "https://example.com/app/id123")
            ),
            alternatives: []
        ))
    }

    @Test("A scan keeps settled rows during checking and removes unseen apps at completion")
    func scanAccumulation() {
        let cached = status("Cached", state: .upToDate)
        let fresh = status("Fresh", state: .upToDate)
        let missing = status("Missing", state: .upToDate)
        var accumulator = ScanAccumulator(previous: [cached.id: cached, missing.id: missing])

        let cachedChanged = accumulator.receive(status("Cached"))
        #expect(!cachedChanged)
        #expect(accumulator.statuses[cached.id]?.state == .upToDate)
        let freshChanged = accumulator.receive(fresh)
        #expect(freshChanged)
        let finished = accumulator.finish()

        #expect(Set(finished.keys) == [cached.id, fresh.id])
    }

    @Test("Failed scans back off; useful scans clear recovery")
    func automaticRecovery() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var recovery = AutomaticCheckRecovery()
        let networkFailure = UpdateState.failed(UpdateError(
            .sourceRequestFailed(.sparkle, detail: "offline")
        ))

        let failedScanCompleted = recovery.recordScan([networkFailure], now: now)
        #expect(!failedScanCompleted)
        #expect(recovery.failedScanRetryAttempt == 1)
        #expect(recovery.retryAt == now.addingTimeInterval(5 * 60))
        let restored = recovery.restoreConnectivity(now: now.addingTimeInterval(10))
        #expect(restored)
        #expect(recovery.retryAt == now.addingTimeInterval(10))
        let usefulScanCompleted = recovery.recordScan([.upToDate], now: now)
        #expect(usefulScanCompleted)
        #expect(recovery == AutomaticCheckRecovery())
    }

    @Test("Individual routing covers hand-off, consent, install, and duplicate suppression")
    func individualPlanning() {
        let direct = outdated("Direct")
        let store = outdated("Store", source: .macAppStore, downloadURL: nil)

        #expect(UpdateRequestPlanning.individual(
            direct,
            hasPendingConfirmation: false,
            isInstalling: false,
            isRunning: false
        ) == .install)
        #expect(UpdateRequestPlanning.individual(
            direct,
            hasPendingConfirmation: false,
            isInstalling: false,
            isRunning: true
        ) == .confirmQuit)
        #expect(UpdateRequestPlanning.individual(
            direct,
            hasPendingConfirmation: false,
            isInstalling: true,
            isRunning: false
        ) == .ignored)
        guard case .handOff(let url) = UpdateRequestPlanning.individual(
            store,
            hasPendingConfirmation: false,
            isInstalling: false,
            isRunning: false
        ) else {
            Issue.record("Expected App Store hand-off")
            return
        }
        #expect(url.scheme == "macappstore")
    }

    @Test("Batch routing separates App Store hand-off and running installable apps")
    func batchPlanning() {
        let closed = outdated("Closed")
        let running = outdated("Running")
        let store = outdated("Store", source: .macAppStore, downloadURL: nil)
        let plan = UpdateRequestPlanning.batch(
            [store, running, closed],
            installing: [],
            isRunning: { $0.id == running.id }
        )

        #expect(plan.handOffToAppStore)
        #expect(plan.installable.map(\.app.name) == ["Running", "Closed"])
        #expect(plan.running.map(\.app.name) == ["Running"])
    }
}
