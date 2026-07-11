import Foundation
import Testing
import FreshlyModels
import FreshlyScanner
import FreshlySources
@testable import FreshlyEngine

private struct StubDiscoverer: AppDiscovering {
    let list: [InstalledApp]

    func apps() -> AsyncStream<InstalledApp> {
        AsyncStream { continuation in
            for app in list {
                continuation.yield(app)
            }
            continuation.finish()
        }
    }
}

private struct FixedSource: UpdateSource {
    let id: SourceID
    let claim: SourceApplicability
    var release: ReleaseInfo?
    var error: UpdateError?

    func applicability(for app: InstalledApp) -> SourceApplicability { claim }

    func latestRelease(for app: InstalledApp) async throws -> ReleaseInfo? {
        if let error { throw error }
        return release
    }
}

private func makeApp(_ bundleID: String, version: AppVersion) -> InstalledApp {
    InstalledApp(
        bundleID: bundleID,
        name: bundleID,
        path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
        version: version,
        sparkleFeedURL: URL(string: "https://example.com/appcast.xml")
    )
}

@Suite("UpdateCoordinator")
struct UpdateCoordinatorTests {
    @Test("Streams a checking state before each final state")
    func emitsCheckingFirst() async {
        let app = makeApp("com.example.One", version: "1.0")
        let source = FixedSource(
            id: .sparkle,
            claim: .authoritative,
            release: ReleaseInfo(version: "2.0", source: .sparkle)
        )
        let coordinator = UpdateCoordinator(
            discoverer: StubDiscoverer(list: [app]),
            registry: SourceRegistry(sources: [source])
        )

        var states: [UpdateState] = []
        for await status in coordinator.checkAll() {
            states.append(status.state)
        }
        #expect(states.first == .checking)
        #expect(states.count == 2)
        if case .outdated(let best, let alternatives) = states.last {
            #expect(best.version == "2.0")
            #expect(alternatives.isEmpty)
        } else {
            Issue.record("Expected outdated, got \(String(describing: states.last))")
        }
    }

    @Test("Equal or older releases resolve to up to date")
    func upToDate() async {
        let app = makeApp("com.example.Two", version: "2.0")
        let source = FixedSource(
            id: .sparkle,
            claim: .authoritative,
            release: ReleaseInfo(version: "2.0", source: .sparkle)
        )
        let coordinator = UpdateCoordinator(
            discoverer: StubDiscoverer(list: [app]),
            registry: SourceRegistry(sources: [source])
        )

        var finalStates: [UpdateState] = []
        for await status in coordinator.checkAll() where status.state != .checking {
            finalStates.append(status.state)
        }
        #expect(finalStates == [.upToDate])
    }

    @Test("Apps no source claims are unsupported")
    func unsupported() async {
        let app = makeApp("com.example.Three", version: "1.0")
        let coordinator = UpdateCoordinator(
            discoverer: StubDiscoverer(list: [app]),
            registry: SourceRegistry(sources: [])
        )

        var finalStates: [UpdateState] = []
        for await status in coordinator.checkAll() where status.state != .checking {
            finalStates.append(status.state)
        }
        #expect(finalStates == [.unsupported])
    }

    @Test("A failing source surfaces as a failed state when nothing answered")
    func failurePropagates() async {
        let app = makeApp("com.example.Four", version: "1.0")
        let source = FixedSource(
            id: .sparkle,
            claim: .authoritative,
            error: UpdateError(.sourceRequestFailed(.sparkle, detail: "offline"))
        )
        let coordinator = UpdateCoordinator(
            discoverer: StubDiscoverer(list: [app]),
            registry: SourceRegistry(sources: [source])
        )

        var finalStates: [UpdateState] = []
        for await status in coordinator.checkAll() where status.state != .checking {
            finalStates.append(status.state)
        }
        #expect(finalStates == [.failed(UpdateError(.sourceRequestFailed(.sparkle, detail: "offline")))])
    }

    @Test("The authoritative source wins; candidates become alternatives")
    func authoritativeWins() {
        let app = makeApp("com.example.Five", version: "1.0")
        let authoritative = ReleaseInfo(version: "1.5", source: .sparkle)
        let candidate = ReleaseInfo(version: "2.0", source: .github)

        let state = UpdateCoordinator.resolve(
            app: app,
            candidates: [authoritative, candidate],
            failures: []
        )
        if case .outdated(let best, let alternatives) = state {
            #expect(best.source == .sparkle)
            #expect(alternatives.map(\.source) == [.github])
        } else {
            Issue.record("Expected outdated, got \(state)")
        }
    }

    @Test("All apps get checked with many apps in flight")
    func checksEveryApp() async {
        let apps = (1...40).map { makeApp("com.example.App\($0)", version: "1.0") }
        let source = FixedSource(
            id: .sparkle,
            claim: .authoritative,
            release: ReleaseInfo(version: "9.9", source: .sparkle)
        )
        let coordinator = UpdateCoordinator(
            discoverer: StubDiscoverer(list: apps),
            registry: SourceRegistry(sources: [source]),
            maxConcurrentChecks: 4
        )

        var finals: Set<String> = []
        for await status in coordinator.checkAll() where status.state != .checking {
            finals.insert(status.app.bundleID)
        }
        #expect(finals.count == 40)
    }
}
