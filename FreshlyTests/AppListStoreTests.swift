import Foundation
import Testing
import FreshlyEngine
import FreshlyModels
@testable import Freshly

@MainActor
private final class InstallerSpy: UpdateInstalling {
    struct Request {
        let release: ReleaseInfo
        let app: InstalledApp
        let quitIfRunning: Bool
    }

    private(set) var requests: [Request] = []

    func install(
        _ release: ReleaseInfo,
        over app: InstalledApp,
        quitIfRunning: Bool
    ) -> AsyncThrowingStream<InstallPhase, Error> {
        requests.append(Request(
            release: release,
            app: app,
            quitIfRunning: quitIfRunning
        ))
        return AsyncThrowingStream { continuation in
            continuation.yield(.installing)
            continuation.finish()
        }
    }
}

@MainActor
private final class URLRecorder {
    private(set) var urls: [URL] = []

    func open(_ url: URL) {
        urls.append(url)
    }
}

@MainActor
private final class ScannerStub: UpdateScanning {
    private(set) var continuations: [AsyncStream<AppUpdateStatus>.Continuation] = []

    func start() async -> AppScanSession {
        let stream = AsyncStream<AppUpdateStatus> { continuation in
            continuations.append(continuation)
        }
        return AppScanSession(installedCaskTokens: [], statuses: stream)
    }

    func yield(_ status: AppUpdateStatus, to scan: Int) {
        continuations[scan].yield(status)
    }

    func finish(_ scan: Int) {
        continuations[scan].finish()
    }
}

@MainActor
private final class NotificationSpy: UpdateNotifying {
    var actionHandler: ((NotificationAction) -> Void)?
    private(set) var batches: [[AppUpdateStatus]] = []

    func notifyNewUpdates(_ fresh: [AppUpdateStatus]) {
        batches.append(fresh)
    }
}

@Suite("AppListStore install routing", .serialized)
@MainActor
struct AppListStoreTests {
    private struct Harness {
        let directory: URL
        let defaultsSuite: String
        let installer: InstallerSpy
        let scanner: ScannerStub
        let notifications: NotificationSpy
        let urlRecorder: URLRecorder
        let store: AppListStore

        func cleanUp() {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeStatus(
        named name: String,
        source: SourceID = .sparkle,
        directDownload: Bool = true
    ) throws -> AppUpdateStatus {
        let app = InstalledApp(
            bundleID: "com.example.\(name)",
            name: name,
            path: URL(filePath: "/Applications/\(name).app"),
            version: "1.0"
        )
        let release = ReleaseInfo(
            version: "2.0",
            source: source,
            downloadURL: directDownload
                ? URL(filePath: "/tmp/\(name).zip")
                : nil,
            releaseNotesURL: URL(filePath: "/app/id123")
        )
        return AppUpdateStatus(app: app, state: .outdated(best: release, alternatives: []))
    }

    private func makeHarness(
        statuses: [AppUpdateStatus],
        isRunning: @escaping (InstalledApp) -> Bool = { _ in false },
        now: @escaping () -> Date = { Date.now }
    ) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-app-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ScanCache(directory: directory).save(statuses)

        let defaultsSuite = "FreshlyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.set(0, forKey: "checkIntervalHours")
        let installer = InstallerSpy()
        let scanner = ScannerStub()
        let notifications = NotificationSpy()
        let urlRecorder = URLRecorder()
        let store = AppListStore(
            installer: installer,
            scanner: scanner,
            notificationManager: notifications,
            applicationSupportDirectory: directory,
            userDefaults: defaults,
            startServices: false,
            openURL: { urlRecorder.open($0) },
            appIsRunning: isRunning,
            now: now
        )
        return Harness(
            directory: directory,
            defaultsSuite: defaultsSuite,
            installer: installer,
            scanner: scanner,
            notifications: notifications,
            urlRecorder: urlRecorder,
            store: store
        )
    }

    private func waitUntil(
        _ description: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(description)")
    }

    @Test("The hosted app process uses the isolated test runtime")
    func isolatedTestRuntime() {
        #expect(AppRuntime.isTesting)
        #expect(AppRuntime.applicationSupportDirectory.path.hasPrefix(
            FileManager.default.temporaryDirectory.path
        ))
    }

    @Test("An individual update starts once and ignores a duplicate request")
    func individualAndDuplicateRequest() async throws {
        let status = try makeStatus(named: "Single")
        let harness = try makeHarness(statuses: [status])
        defer { harness.cleanUp() }

        #expect(harness.store.requestUpdate(for: status) == .started)
        #expect(harness.store.installing[status.id] == .waiting)
        #expect(harness.store.requestUpdate(for: status) == .ignored)

        await waitUntil("one installer dispatch") {
            harness.installer.requests.count == 1
        }
        #expect(harness.installer.requests[0].app.id == status.id)
        #expect(!harness.installer.requests[0].quitIfRunning)
        await waitUntil("the individual install to finish") {
            harness.store.installing.isEmpty
        }
    }

    @Test("Update All dispatches every installable app sequentially")
    func updateAll() async throws {
        let first = try makeStatus(named: "Alpha")
        let second = try makeStatus(named: "Beta")
        let harness = try makeHarness(statuses: [second, first])
        defer { harness.cleanUp() }

        #expect(harness.store.updateAll() == .started)
        #expect(harness.store.installing.count == 2)

        await waitUntil("two installer dispatches") {
            harness.installer.requests.count == 2
        }
        #expect(harness.installer.requests.map(\.app.name) == ["Alpha", "Beta"])
        #expect(harness.installer.requests.allSatisfy { !$0.quitIfRunning })
        await waitUntil("the batch to finish") {
            harness.store.installing.isEmpty
        }
    }

    @Test("A running app waits for confirmation and then requests quit")
    func runningAppConfirmation() async throws {
        let status = try makeStatus(named: "Running")
        let harness = try makeHarness(statuses: [status]) { $0.id == status.id }
        defer { harness.cleanUp() }

        #expect(harness.store.requestUpdate(for: status) == .requiresQuitConfirmation)
        #expect(harness.store.isQuitConfirmationPresented)
        #expect(harness.installer.requests.isEmpty)

        harness.store.confirmQuitAndUpdate()
        #expect(!harness.store.isQuitConfirmationPresented)
        #expect(harness.store.installing[status.id] == .waiting)

        await waitUntil("the confirmed installer dispatch") {
            harness.installer.requests.count == 1
        }
        #expect(harness.installer.requests[0].quitIfRunning)
        await waitUntil("the confirmed install to finish") {
            harness.store.installing.isEmpty
        }
    }

    @Test("Update All waits once for running apps before dispatching the batch")
    func batchRunningAppConfirmation() async throws {
        let first = try makeStatus(named: "Closed")
        let second = try makeStatus(named: "RunningInBatch")
        let harness = try makeHarness(statuses: [first, second]) { $0.id == second.id }
        defer { harness.cleanUp() }

        #expect(harness.store.updateAll() == .requiresQuitConfirmation)
        #expect(harness.store.isQuitConfirmationPresented)
        #expect(harness.store.installing.isEmpty)
        #expect(harness.installer.requests.isEmpty)

        harness.store.confirmQuitAndUpdate()
        #expect(!harness.store.isQuitConfirmationPresented)
        #expect(harness.store.installing.count == 2)

        await waitUntil("the confirmed batch dispatches") {
            harness.installer.requests.count == 2
        }
        let allRequestsAllowQuit = harness.installer.requests.allSatisfy { $0.quitIfRunning }
        #expect(allRequestsAllowQuit)
        await waitUntil("the confirmed batch to finish") {
            harness.store.installing.isEmpty
        }
    }

    @Test("A Mac App Store update is handed off without an install pipeline")
    func appStoreHandOff() throws {
        let status = try makeStatus(
            named: "StoreApp",
            source: .macAppStore,
            directDownload: false
        )
        let harness = try makeHarness(statuses: [status])
        defer { harness.cleanUp() }

        #expect(harness.store.requestUpdate(for: status) == .handedOff)
        #expect(harness.installer.requests.isEmpty)
        #expect(harness.urlRecorder.urls.count == 1)
        #expect(harness.urlRecorder.urls[0].scheme == "macappstore")
    }

    @Test("A superseded scan cannot overwrite the current scan")
    func staleScanCancellation() async throws {
        let stale = try makeStatus(named: "Stale")
        let current = try makeStatus(named: "Current")
        let harness = try makeHarness(statuses: [])
        defer { harness.cleanUp() }

        harness.store.refresh()
        await waitUntil("the first scan to start") {
            harness.scanner.continuations.count == 1
        }
        harness.store.refresh()
        await waitUntil("the replacement scan to start") {
            harness.scanner.continuations.count == 2
        }

        harness.scanner.yield(stale, to: 0)
        harness.scanner.finish(0)
        harness.scanner.yield(current, to: 1)
        harness.scanner.finish(1)

        await waitUntil("the replacement scan to finish") {
            !harness.store.isScanning
        }
        #expect(Set(harness.store.statuses.keys) == [current.id])
    }

    @Test("Only automatic scans notify about newly outdated apps")
    func automaticNotificationPolicy() async throws {
        let existing = try makeStatus(named: "Existing")
        let manual = try makeStatus(named: "Manual")
        let automatic = try makeStatus(named: "Automatic")
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let harness = try makeHarness(statuses: [existing], now: { fixedNow })
        defer { harness.cleanUp() }

        harness.store.refresh(origin: .userInitiated)
        await waitUntil("the manual scan to start") {
            harness.scanner.continuations.count == 1
        }
        harness.scanner.yield(manual, to: 0)
        harness.scanner.finish(0)
        await waitUntil("the manual scan to finish") {
            !harness.store.isScanning
        }
        #expect(harness.notifications.batches.isEmpty)
        #expect(harness.store.lastCheckedAt == fixedNow)

        harness.store.refresh(origin: .automatic)
        await waitUntil("the automatic scan to start") {
            harness.scanner.continuations.count == 2
        }
        harness.scanner.yield(automatic, to: 1)
        harness.scanner.finish(1)
        await waitUntil("the automatic scan to finish") {
            !harness.store.isScanning
        }

        #expect(harness.notifications.batches.count == 1)
        #expect(harness.notifications.batches[0].map(\.id) == [automatic.id])
    }
}
