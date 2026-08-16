import AppKit
import Foundation
import Network
import Observation
import FreshlyEngine
import FreshlyInstaller
import FreshlyModels
import FreshlyScanner

/// Drives the main window and the menu bar extra: owns the scan lifecycle,
/// the streamed per-app statuses, and running installs.
@Observable
@MainActor
final class AppListStore {
    private(set) var statuses: [URL: AppUpdateStatus] = [:]
    private(set) var isScanning = false
    /// When the last scan finished. Persisted so a freshly launched window,
    /// which opens on the cached list, can still say when it was last checked.
    private(set) var lastCheckedAt: Date?
    /// Phase of each in-flight install, keyed by app id.
    private(set) var installing: [URL: InstallPhase] = [:]
    /// Stable one-based positions for installs started by Update All.
    private(set) var installQueuePositions: [URL: Int] = [:]
    /// Last install failure per app; cleared when a new attempt starts.
    private(set) var installErrors: [URL: UpdateError] = [:]
    /// Set when an individual or bulk update needs consent to quit apps.
    private(set) var pendingQuitConfirmation: QuitConfirmation?
    var showPermissionAlert = false

    /// Past update attempts, newest first, shown in the History window.
    private(set) var history: [UpdateRecord] = []

    let skipStore: SkipStore
    let overrideStore: OverrideStore
    private let installer: any UpdateInstalling
    private let scanner: any UpdateScanning
    private let notificationManager: (any UpdateNotifying)?
    private let networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "com.rux.Freshly.network-monitor")
    private let scanCache: ScanCache
    private let historyStore: UpdateHistory
    private let userDefaults: UserDefaults
    private let openURL: (URL) -> Void
    private let appIsRunning: (InstalledApp) -> Bool
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    /// Casks installed through brew, refreshed each scan; decides whether a
    /// Homebrew update goes through `brew upgrade` or the direct pipeline.
    private var installedCaskTokens: Set<String> = []
    private var scanTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var wakeObserverTask: Task<Void, Never>?
    private var automaticRecovery: AutomaticCheckRecovery
    private var isNetworkAvailable: Bool?
    private var generation = 0
    private var installReservations = InstallReservations<URL>()

    /// Who asked for a refresh. Automatic checks keep the previous list on
    /// screen and notify about anything newly outdated; manual ones don't
    /// notify — the user is already looking.
    enum RefreshOrigin {
        case userInitiated
        case automatic
    }

    enum QuitConfirmation {
        case single(AppUpdateStatus)
        case batch(targets: [AppUpdateStatus], running: [AppUpdateStatus])
    }

    init(
        installer: any UpdateInstalling = UpdateInstaller(),
        scanner: any UpdateScanning = LiveUpdateScanner(),
        notificationManager: (any UpdateNotifying)? = nil,
        applicationSupportDirectory: URL = AppRuntime.applicationSupportDirectory,
        userDefaults: UserDefaults = AppRuntime.userDefaults,
        startServices: Bool = !AppRuntime.isTesting,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        appIsRunning: @escaping (InstalledApp) -> Bool = {
            !RunningApps.instances(of: $0).isEmpty
        },
        now: @escaping () -> Date = { Date.now },
        sleep: @escaping (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(for: .seconds(delay))
        }
    ) {
        self.installer = installer
        self.scanner = scanner
        self.userDefaults = userDefaults
        self.openURL = openURL
        self.appIsRunning = appIsRunning
        self.now = now
        self.sleep = sleep
        skipStore = SkipStore(directory: applicationSupportDirectory)
        overrideStore = OverrideStore(directory: applicationSupportDirectory)
        scanCache = ScanCache(directory: applicationSupportDirectory)
        historyStore = UpdateHistory(directory: applicationSupportDirectory)
        self.notificationManager = notificationManager ?? (startServices ? NotificationManager() : nil)
        networkMonitor = startServices ? NWPathMonitor() : nil
        automaticRecovery = AutomaticCheckRecovery(
            retryAt: userDefaults.object(forKey: "automaticCheckRetryAt") as? Date,
            failedScanRetryAttempt: userDefaults.integer(forKey: "automaticCheckRetryAttempt")
        )

        // Open instantly with the last scan while a fresh one runs.
        statuses = Dictionary(
            scanCache.load().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        history = historyStore.load()
        lastCheckedAt = userDefaults.object(forKey: "lastCheckedAt") as? Date
        rebuildSections()
        if startServices {
            applySchedule()
            observeSystemWake()
            observeConnectivity()
            notificationManager?.actionHandler = { [weak self] action in
                self?.handleNotificationAction(action)
            }
        }
    }

    /// The five sections the UI renders, derived from `statuses` with the
    /// user's channel overrides and skips applied. Stored (not computed) and
    /// rebuilt only when their inputs change: `ContentView` reads them many
    /// times per body evaluation and a streaming scan evaluates the body
    /// often, so recomputing the O(n) projection on every read dominated the
    /// main actor.
    private(set) var outdated: [AppUpdateStatus] = []
    private(set) var checking: [AppUpdateStatus] = []
    private(set) var upToDate: [AppUpdateStatus] = []
    private(set) var skipped: [AppUpdateStatus] = []
    /// Unsupported and failed apps — shown so the user knows what Freshly
    /// cannot check (yet) instead of silently hiding them.
    private(set) var notCheckable: [AppUpdateStatus] = []

    var outdatedCount: Int { outdated.count }
    var isInstallingAnything: Bool { !installing.isEmpty }
    func queuePosition(for id: URL) -> Int? { installQueuePositions[id] }
    var isAutomaticRetryPending: Bool { automaticRecovery.retryAt != nil }
    var isQuitConfirmationPresented: Bool {
        get { pendingQuitConfirmation != nil }
        set {
            if !newValue {
                pendingQuitConfirmation = nil
            }
        }
    }

    // MARK: - Scanning

    func refresh(origin: RefreshOrigin = .userInitiated) {
        generation += 1
        let current = generation
        scanTask?.cancel()
        installErrors = [:]
        isScanning = true

        // Snapshot for the new-updates diff (with skips applied, so a
        // skipped version never notifies).
        let previouslyOutdated = outdated
        var accumulator = ScanAccumulator(previous: statuses)

        scanTask = Task {
            let session = await scanner.start()
            guard generation == current else { return }
            installedCaskTokens = session.installedCaskTokens

            for await status in session.statuses {
                guard generation == current else { return }
                if accumulator.receive(status) {
                    statuses = accumulator.statuses
                    rebuildSections()
                }
            }
            guard generation == current else { return }
            statuses = accumulator.finish()
            rebuildSections()
            isScanning = false
            scanCache.save(statuses.values)

            let completed = automaticRecovery.recordScan(
                statuses.values.map(\.state),
                now: now()
            )
            persistAutomaticRetryState()
            if completed {
                lastCheckedAt = now()
                userDefaults.set(lastCheckedAt, forKey: "lastCheckedAt")
            }
            applySchedule()

            if origin == .automatic {
                notificationManager?.notifyNewUpdates(
                    AppUpdateStatus.newlyOutdated(in: outdated, comparedTo: previouslyOutdated)
                )
            }
        }
    }

    /// (Re)arms the next check from the last completed scan. 0 hours means
    /// manual-only. A busy app retries shortly instead of losing a full
    /// interval.
    var nextAutomaticCheckAt: Date? {
        let hours = userDefaults.object(forKey: "checkIntervalHours") as? Int ?? 6
        let now = now()
        return AutomaticCheckSchedule.nextAction(
            intervalHours: hours,
            lastCheckedAt: lastCheckedAt,
            now: now,
            isBusy: isScanning || isInstallingAnything,
            retryAt: automaticRecovery.retryAt
        ).date(relativeTo: now)
    }

    func applySchedule() {
        schedulerTask?.cancel()
        let hours = userDefaults.object(forKey: "checkIntervalHours") as? Int ?? 6
        guard hours > 0 else {
            automaticRecovery.clear()
            persistAutomaticRetryState()
            schedulerTask = nil
            return
        }
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let action = AutomaticCheckSchedule.nextAction(
                    intervalHours: hours,
                    lastCheckedAt: self.lastCheckedAt,
                    now: self.now(),
                    isBusy: self.isScanning || self.isInstallingAnything,
                    retryAt: self.automaticRecovery.retryAt
                )
                switch action {
                case .disabled:
                    return
                case .wait(let delay), .retryAfter(let delay):
                    try? await self.sleep(delay)
                case .checkNow:
                    guard self.isNetworkAvailable != false else {
                        self.scheduleAutomaticRetry()
                        self.applySchedule()
                        return
                    }
                    self.automaticRecovery.beginScheduledCheck()
                    self.persistAutomaticRetryState()
                    self.refresh(origin: .automatic)
                    return
                }
            }
        }
    }

    private func observeSystemWake() {
        wakeObserverTask = Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didWakeNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { return }
                self?.applySchedule()
            }
        }
    }

    private func observeConnectivity() {
        guard let networkMonitor else { return }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = isAvailable
                guard wasAvailable == false,
                      isAvailable,
                      self.automaticRecovery.restoreConnectivity(now: self.now()) else { return }
                self.persistAutomaticRetryState()
                self.applySchedule()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func scheduleAutomaticRetry() {
        automaticRecovery.scheduleRetry(now: now())
        persistAutomaticRetryState()
    }

    private func persistAutomaticRetryState() {
        userDefaults.set(automaticRecovery.retryAt, forKey: "automaticCheckRetryAt")
        userDefaults.set(
            automaticRecovery.failedScanRetryAttempt,
            forKey: "automaticCheckRetryAttempt"
        )
    }

    // MARK: - Installing

    @discardableResult
    func requestUpdate(for status: AppUpdateStatus) -> UpdateRequestResult {
        let plan = UpdateRequestPlanning.individual(
            status,
            hasPendingConfirmation: pendingQuitConfirmation != nil,
            isInstalling: installing[status.id] != nil,
            isRunning: isRunning(status.app)
        )
        switch plan {
        case .ignored:
            return .ignored
        case .handOff(let url):
            openURL(url)
            return .handedOff
        case .confirmQuit:
            pendingQuitConfirmation = .single(status)
            return .requiresQuitConfirmation
        case .install:
            return startInstall(status, quitIfRunning: false) ? .started : .ignored
        }
    }

    private func handleNotificationAction(_ action: NotificationAction) {
        switch action {
        case .openFreshly:
            FreshlyAppDelegate.showMainWindow()
        case .updateAll:
            guard !outdated.isEmpty else {
                FreshlyAppDelegate.showMainWindow()
                return
            }
            if updateAll() == .requiresQuitConfirmation {
                FreshlyAppDelegate.showMainWindow()
            }
        case .updateApp(let path):
            guard let status = outdated.first(where: { $0.app.path.path == path }) else {
                FreshlyAppDelegate.showMainWindow()
                return
            }
            switch requestUpdate(for: status) {
            case .requiresQuitConfirmation, .ignored:
                FreshlyAppDelegate.showMainWindow()
            case .started, .handedOff:
                break
            }
        }
    }

    func confirmQuitAndUpdate() {
        guard let confirmation = pendingQuitConfirmation else { return }
        pendingQuitConfirmation = nil
        switch confirmation {
        case .single(let status):
            startInstall(status, quitIfRunning: true)
        case .batch(let targets, _):
            startBatch(targets, quitIfRunning: true)
        }
    }

    func dismissQuitConfirmation() {
        pendingQuitConfirmation = nil
    }

    /// Sequential bulk update of everything currently outdated. When one or
    /// more targets are running, the whole installable batch waits for one
    /// explicit confirmation instead of recording each app as a failed
    /// update. App Store updates are handed off immediately.
    @discardableResult
    func updateAll() -> UpdateRequestResult {
        guard pendingQuitConfirmation == nil else { return .ignored }
        let plan = UpdateRequestPlanning.batch(
            outdated,
            installing: Set(installing.keys),
            isRunning: isRunning
        )
        if plan.handOffToAppStore,
           let updates = URL(string: "macappstore://showUpdatesPage") {
            openURL(updates)
        }

        guard !plan.installable.isEmpty else {
            return plan.handOffToAppStore ? .handedOff : .ignored
        }

        guard plan.running.isEmpty else {
            pendingQuitConfirmation = .batch(targets: plan.installable, running: plan.running)
            return .requiresQuitConfirmation
        }

        startBatch(plan.installable, quitIfRunning: false)
        return .started
    }

    /// Claims the app's install slot before creating the unstructured task.
    /// Because the store is MainActor-isolated, a second request observes
    /// `.waiting` immediately and cannot launch a duplicate pipeline.
    @discardableResult
    private func startInstall(_ status: AppUpdateStatus, quitIfRunning: Bool) -> Bool {
        guard installReservations.reserve(status.id) else { return false }
        installQueuePositions[status.id] = nil
        installing[status.id] = .waiting
        Task {
            await self.runInstall(status, quitIfRunning: quitIfRunning)
        }
        return true
    }

    private func startBatch(_ targets: [AppUpdateStatus], quitIfRunning: Bool) {
        let reservedTargets = targets.filter { installReservations.reserve($0.id) }
        for (offset, target) in reservedTargets.enumerated() {
            installQueuePositions[target.id] = offset + 1
            installing[target.id] = .waiting
        }
        Task {
            for target in reservedTargets {
                await self.runInstall(target, quitIfRunning: quitIfRunning)
            }
        }
    }

    private func runInstall(_ status: AppUpdateStatus, quitIfRunning: Bool) async {
        let id = status.id
        defer {
            installReservations.release(id)
            installing[id] = nil
            installQueuePositions[id] = nil
        }
        guard case .outdated(let best, _) = status.state else {
            return
        }
        // Casks installed through brew upgrade through brew, keeping its
        // bookkeeping consistent; everything else uses the direct pipeline.
        if InstallRouting.usesBrewUpgrade(best, installedCaskTokens: installedCaskTokens),
           let token = best.caskToken, let brew = HomebrewClient.detect() {
            await runBrewUpgrade(status, token: token, client: brew, quitIfRunning: quitIfRunning)
            return
        }
        installErrors[id] = nil
        installing[id] = .downloading(fraction: nil)

        do {
            for try await phase in installer.install(best, over: status.app, quitIfRunning: quitIfRunning) {
                installing[id] = phase
            }
            let refreshed = AppScanner.inspect(appAt: status.app.path) ?? status.app
            statuses[id] = AppUpdateStatus(app: refreshed, state: .upToDate)
            rebuildSections()
            scanCache.save(statuses.values)
            record(status, release: best, outcome: .installed)
        } catch let error as UpdateError {
            installErrors[id] = error
            record(status, release: best, outcome: .failed(error))
            if error.code == .permissionDenied {
                showPermissionAlert = true
            }
        } catch {
            let error = UpdateError(.underlying(detail: error.localizedDescription))
            installErrors[id] = error
            record(status, release: best, outcome: .failed(error))
        }
    }

    private func runBrewUpgrade(
        _ status: AppUpdateStatus,
        token: String,
        client: HomebrewClient,
        quitIfRunning: Bool
    ) async {
        guard case .outdated(let best, _) = status.state else {
            return
        }
        let id = status.id
        installErrors[id] = nil
        installing[id] = .waiting
        do {
            // Same quit-and-relaunch contract as the direct pipeline —
            // graceful, then forced if the app ignores it.
            let wasRunning = try await RunningApps.quitIfNeeded(status.app, allowed: quitIfRunning)

            try await client.upgradeCask(token) { phase in
                await self.setInstallPhase(phase, for: id)
            }

            if wasRunning {
                installing[id] = .relaunching
                await RunningApps.launch(appAt: status.app.path)
            }
            let refreshed = AppScanner.inspect(appAt: status.app.path) ?? status.app
            statuses[id] = AppUpdateStatus(app: refreshed, state: .upToDate)
            rebuildSections()
            scanCache.save(statuses.values)
            record(status, release: best, outcome: .installed)
        } catch let error as UpdateError {
            installErrors[id] = error
            record(status, release: best, outcome: .failed(error))
        } catch {
            let error = UpdateError(.underlying(detail: error.localizedDescription))
            installErrors[id] = error
            record(status, release: best, outcome: .failed(error))
        }
    }

    private func setInstallPhase(_ phase: InstallPhase, for id: URL) {
        installing[id] = phase
    }

    // MARK: - History

    private func record(_ status: AppUpdateStatus, release: ReleaseInfo, outcome: UpdateRecord.Outcome) {
        history = historyStore.append(UpdateRecord(
            bundleID: status.app.bundleID,
            appName: status.app.name,
            fromVersion: status.app.version,
            toVersion: release.version,
            source: release.source,
            outcome: outcome
        ))
    }

    func clearHistory() {
        historyStore.clear()
        history = []
    }

    // MARK: - Skipping

    func skipVersion(for status: AppUpdateStatus) {
        guard case .outdated(let best, _) = status.state else { return }
        skipStore.skip(version: best.version, forBundleID: status.app.bundleID)
        rebuildSections()
    }

    func stopSkipping(_ status: AppUpdateStatus) {
        skipStore.unskip(bundleID: status.app.bundleID)
        rebuildSections()
    }

    // MARK: - Source override

    func setPreferredSource(_ source: SourceID, for status: AppUpdateStatus) {
        overrideStore.setPreferredSource(source, for: status.app.bundleID)
        rebuildSections()
    }

    // MARK: - Helpers

    private func isRunning(_ app: InstalledApp) -> Bool {
        appIsRunning(app)
    }

    /// Rebuilds the five sections in one pass from the only inputs that shape
    /// them — `statuses`, the channel overrides, and the skip list — so reads
    /// are free. Call this after mutating any of those. Order matters: the
    /// override picks the primary release first, then the skip check runs
    /// against that release's version.
    private func rebuildSections() {
        let sections = AppStatusSections.classify(
            statuses.values,
            preferredSource: { overrideStore.preferredSource(for: $0) },
            skippedVersion: { skipStore.skippedVersion(for: $0) }
        )
        outdated = sections.outdated
        checking = sections.checking
        upToDate = sections.upToDate
        skipped = sections.skipped
        notCheckable = sections.notCheckable
    }
}
