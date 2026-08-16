import AppKit
import Foundation
import Network
import Observation
import FreshlyEngine
import FreshlyInstaller
import FreshlyModels
import FreshlyScanner
import FreshlySources

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
    private let notificationManager: NotificationManager?
    private let networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "com.rux.Freshly.network-monitor")
    private let scanCache: ScanCache
    private let historyStore: UpdateHistory
    private let userDefaults: UserDefaults
    private let openURL: (URL) -> Void
    private let appIsRunning: (InstalledApp) -> Bool
    /// Casks installed through brew, refreshed each scan; decides whether a
    /// Homebrew update goes through `brew upgrade` or the direct pipeline.
    private var installedCaskTokens: Set<String> = []
    private var scanTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var wakeObserverTask: Task<Void, Never>?
    private var automaticRetryAt: Date?
    private var failedScanRetryAttempt = 0
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
        applicationSupportDirectory: URL = AppRuntime.applicationSupportDirectory,
        userDefaults: UserDefaults = AppRuntime.userDefaults,
        startServices: Bool = !AppRuntime.isTesting,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        appIsRunning: @escaping (InstalledApp) -> Bool = {
            !RunningApps.instances(of: $0).isEmpty
        }
    ) {
        self.installer = installer
        self.userDefaults = userDefaults
        self.openURL = openURL
        self.appIsRunning = appIsRunning
        skipStore = SkipStore(directory: applicationSupportDirectory)
        overrideStore = OverrideStore(directory: applicationSupportDirectory)
        scanCache = ScanCache(directory: applicationSupportDirectory)
        historyStore = UpdateHistory(directory: applicationSupportDirectory)
        notificationManager = startServices ? NotificationManager() : nil
        networkMonitor = startServices ? NWPathMonitor() : nil

        // Open instantly with the last scan while a fresh one runs.
        statuses = Dictionary(
            scanCache.load().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        history = historyStore.load()
        lastCheckedAt = userDefaults.object(forKey: "lastCheckedAt") as? Date
        automaticRetryAt = userDefaults.object(
            forKey: "automaticCheckRetryAt"
        ) as? Date
        failedScanRetryAttempt = userDefaults.integer(
            forKey: "automaticCheckRetryAttempt"
        )
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
    var isAutomaticRetryPending: Bool { automaticRetryAt != nil }
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
        var seen = Set<URL>()

        scanTask = Task {
            let definitions = await Self.currentDefinitions()

            // Registration order breaks authoritative ties: an app with
            // both a receipt and a Sparkle feed updates through the App
            // Store; the Caskroom outranks a mere matching cask; a
            // brew-installed Electron app keeps updating through brew so
            // its bookkeeping stays honest.
            let caskTokens = Caskroom.detect()?.installedTokens() ?? []
            let homebrewEntries = try? await HomebrewCatalog().loadEntries()
            let sources = SourceAssembly.sources(
                homebrewEntries: homebrewEntries,
                installedCaskTokens: caskTokens,
                definitionCaskTokens: definitions.caskTokens,
                githubRepos: definitions.githubRepos,
                githubToken: TokenStore.load()
            )
            guard generation == current else { return }
            installedCaskTokens = caskTokens

            let coordinator = UpdateCoordinator(
                discoverer: EnrichingDiscoverer(base: AppScanner()) { definitions.enrich($0) },
                registry: SourceRegistry(sources: sources)
            )
            for await status in coordinator.checkAll() {
                guard generation == current else { return }
                seen.insert(status.id)
                // Keep the previous settled state on screen until this
                // scan's verdict arrives — no flash of "Checking".
                if status.state == .checking, statuses[status.id] != nil {
                    continue
                }
                statuses[status.id] = status
                rebuildSections()
            }
            guard generation == current else { return }
            statuses = statuses.filter { seen.contains($0.key) }
            rebuildSections()
            isScanning = false
            scanCache.save(statuses.values)

            if AutomaticCheckSchedule.shouldRetryAfterFailedScan(
                statuses.values.map(\.state)
            ) {
                scheduleAutomaticRetry()
            } else {
                automaticRetryAt = nil
                failedScanRetryAttempt = 0
                persistAutomaticRetryState()
                lastCheckedAt = .now
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
        let now = Date.now
        return AutomaticCheckSchedule.nextAction(
            intervalHours: hours,
            lastCheckedAt: lastCheckedAt,
            now: now,
            isBusy: isScanning || isInstallingAnything,
            retryAt: automaticRetryAt
        ).date(relativeTo: now)
    }

    func applySchedule() {
        schedulerTask?.cancel()
        let hours = userDefaults.object(forKey: "checkIntervalHours") as? Int ?? 6
        guard hours > 0 else {
            automaticRetryAt = nil
            failedScanRetryAttempt = 0
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
                    now: .now,
                    isBusy: self.isScanning || self.isInstallingAnything,
                    retryAt: self.automaticRetryAt
                )
                switch action {
                case .disabled:
                    return
                case .wait(let delay), .retryAfter(let delay):
                    try? await Task.sleep(for: .seconds(delay))
                case .checkNow:
                    guard self.isNetworkAvailable != false else {
                        self.scheduleAutomaticRetry()
                        self.applySchedule()
                        return
                    }
                    self.automaticRetryAt = nil
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
                      self.automaticRetryAt != nil else { return }
                self.automaticRetryAt = .now
                self.persistAutomaticRetryState()
                self.applySchedule()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func scheduleAutomaticRetry() {
        let retryInterval = AutomaticCheckSchedule.failedScanRetryInterval(
            attempt: failedScanRetryAttempt
        )
        failedScanRetryAttempt += 1
        automaticRetryAt = Date.now.addingTimeInterval(retryInterval)
        persistAutomaticRetryState()
    }

    private func persistAutomaticRetryState() {
        userDefaults.set(automaticRetryAt, forKey: "automaticCheckRetryAt")
        userDefaults.set(failedScanRetryAttempt, forKey: "automaticCheckRetryAttempt")
    }

    // MARK: - Installing

    @discardableResult
    func requestUpdate(for status: AppUpdateStatus) -> UpdateRequestResult {
        guard pendingQuitConfirmation == nil,
              case .outdated(let best, _) = status.state,
              installing[status.id] == nil else {
            return .ignored
        }
        // Mac App Store updates cannot be installed by third parties since
        // macOS Tahoe 26.1 — hand off to the App Store instead.
        if best.source == .macAppStore, best.downloadURL == nil {
            openAppStore(for: best)
            return .handedOff
        }
        // A release without a direct download (e.g. a GitHub release with
        // no recognizable archive asset) hands off to its page.
        if best.downloadURL == nil, let page = best.releaseNotesURL {
            openURL(page)
            return .handedOff
        }
        if isRunning(status.app) {
            pendingQuitConfirmation = .single(status)
            return .requiresQuitConfirmation
        }
        return startInstall(status, quitIfRunning: false) ? .started : .ignored
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

    private func openAppStore(for release: ReleaseInfo) {
        // Prefer the app's product page inside the App Store app; fall back
        // to the Updates page.
        if let page = release.releaseNotesURL,
           var components = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            components.scheme = "macappstore"
            if let url = components.url {
                openURL(url)
                return
            }
        }
        if let updates = URL(string: "macappstore://showUpdatesPage") {
            openURL(updates)
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
        let targets = outdated.filter { installing[$0.id] == nil }
        var installable: [AppUpdateStatus] = []
        var appStoreCount = 0

        for target in targets {
            guard case .outdated(let best, _) = target.state else { continue }
            if best.source == .macAppStore, best.downloadURL == nil {
                appStoreCount += 1
            } else {
                installable.append(target)
            }
        }

        if appStoreCount > 0, let updates = URL(string: "macappstore://showUpdatesPage") {
            openURL(updates)
        }

        guard !installable.isEmpty else {
            return appStoreCount > 0 ? .handedOff : .ignored
        }

        let running = installable.filter { isRunning($0.app) }
        guard running.isEmpty else {
            pendingQuitConfirmation = .batch(targets: installable, running: running)
            return .requiresQuitConfirmation
        }

        startBatch(installable, quitIfRunning: false)
        return .started
    }

    /// Claims the app's install slot before creating the unstructured task.
    /// Because the store is MainActor-isolated, a second request observes
    /// `.waiting` immediately and cannot launch a duplicate pipeline.
    @discardableResult
    private func startInstall(_ status: AppUpdateStatus, quitIfRunning: Bool) -> Bool {
        guard installReservations.reserve(status.id) else { return false }
        installing[status.id] = .waiting
        Task {
            await self.runInstall(status, quitIfRunning: quitIfRunning)
        }
        return true
    }

    private func startBatch(_ targets: [AppUpdateStatus], quitIfRunning: Bool) {
        let reservedTargets = targets.filter { installReservations.reserve($0.id) }
        for target in reservedTargets {
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

            installing[id] = .installing
            try await client.upgradeCask(token)

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

    /// The community definitions shipped inside the app bundle (the
    /// repository's `Definitions/` directory, copied in as a resource).
    private static func bundledDefinitions() -> DefinitionsCatalog {
        guard let directory = Bundle.main.url(forResource: "Definitions", withExtension: nil) else {
            return DefinitionsCatalog(definitions: [])
        }
        return DefinitionsCatalog.load(from: directory)
    }

    /// The bundled catalog extended — and, per app, overridden — by the
    /// repository's packed catalog, refreshed on every scan. An unchanged
    /// remote catalog costs one ETag 304; an unreachable one costs
    /// nothing but this scan's staleness.
    private static func currentDefinitions() async -> DefinitionsCatalog {
        await DefinitionsProvider().current(bundled: bundledDefinitions())
    }

    /// Rebuilds the five sections in one pass from the only inputs that shape
    /// them — `statuses`, the channel overrides, and the skip list — so reads
    /// are free. Call this after mutating any of those. Order matters: the
    /// override picks the primary release first, then the skip check runs
    /// against that release's version.
    private func rebuildSections() {
        let display = statuses.values.map { raw -> AppUpdateStatus in
            let status = raw.preferring(overrideStore.preferredSource(for: raw.app.bundleID))
            if case .outdated(let best, _) = status.state,
               skipStore.skippedVersion(for: status.app.bundleID) == best.version {
                var skipped = status
                skipped.state = .skipped(untilVersion: best.version)
                return skipped
            }
            return status
        }

        func section(_ matching: (UpdateState) -> Bool) -> [AppUpdateStatus] {
            display
                .filter { matching($0.state) }
                .sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
        }

        outdated = section { if case .outdated = $0 { true } else { false } }
        checking = section { $0 == .checking }
        upToDate = section { $0 == .upToDate }
        skipped = section { if case .skipped = $0 { true } else { false } }
        notCheckable = section {
            switch $0 {
            case .unsupported, .failed: true
            default: false
            }
        }
    }
}
