import Foundation
import Testing
import FreshlyModels
@testable import FreshlyEngine

private func makeStatus(
    _ bundleID: String,
    state: UpdateState
) -> AppUpdateStatus {
    AppUpdateStatus(
        app: InstalledApp(
            bundleID: bundleID,
            name: bundleID,
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            version: "1.0",
            build: "100",
            signature: SignatureInfo(status: .signed, teamID: "TEAM123"),
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml")
        ),
        state: state
    )
}

@Suite("Scan cache and state codability")
struct ScanCacheTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "FreshlyScanCache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Every state round-trips through the cache intact")
    func roundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ScanCache(directory: directory)

        let statuses = [
            makeStatus("com.example.A", state: .outdated(
                best: ReleaseInfo(version: "2.0", build: "200", edSignature: "sig==", source: .sparkle,
                                  downloadURL: URL(string: "https://example.com/a.zip")),
                alternatives: [ReleaseInfo(version: "2.0", caskToken: "a", source: .homebrew)]
            )),
            makeStatus("com.example.B", state: .upToDate),
            makeStatus("com.example.C", state: .failed(UpdateError(.sourceRequestFailed(.sparkle, detail: "offline")))),
            makeStatus("com.example.D", state: .skipped(untilVersion: "3.0")),
            makeStatus("com.example.E", state: .unsupported),
        ]
        cache.save(statuses)
        let loaded = cache.load()
        #expect(Set(loaded) == Set(statuses))
    }

    @Test("Transient checking states are not persisted")
    func checkingDropped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ScanCache(directory: directory)

        cache.save([
            makeStatus("com.example.A", state: .upToDate),
            makeStatus("com.example.B", state: .checking),
        ])
        let loaded = cache.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.app.bundleID == "com.example.A")
    }

    @Test("A missing or corrupt cache loads as empty")
    func missingOrCorrupt() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ScanCache(directory: directory)
        #expect(cache.load().isEmpty)

        try Data("garbage".utf8).write(to: directory.appending(path: "last-scan.json"))
        #expect(cache.load().isEmpty)
    }
}

@Suite("Newly outdated diff")
struct NewlyOutdatedTests {
    private let release2 = ReleaseInfo(version: "2.0", source: .sparkle)
    private let release3 = ReleaseInfo(version: "3.0", source: .sparkle)

    @Test("A new outdated app is reported; an unchanged one is not")
    func basicDiff() {
        let previous = [makeStatus("com.example.Old", state: .outdated(best: release2, alternatives: []))]
        let current = [
            makeStatus("com.example.Old", state: .outdated(best: release2, alternatives: [])),
            makeStatus("com.example.New", state: .outdated(best: release2, alternatives: [])),
        ]
        let fresh = AppUpdateStatus.newlyOutdated(in: current, comparedTo: previous)
        #expect(fresh.map(\.app.bundleID) == ["com.example.New"])
    }

    @Test("A newer version of an already-outdated app notifies again")
    func versionBump() {
        let previous = [makeStatus("com.example.App", state: .outdated(best: release2, alternatives: []))]
        let current = [makeStatus("com.example.App", state: .outdated(best: release3, alternatives: []))]
        #expect(AppUpdateStatus.newlyOutdated(in: current, comparedTo: previous).count == 1)
    }

    @Test("Non-outdated states never notify")
    func nonOutdatedIgnored() {
        let current = [
            makeStatus("com.example.A", state: .upToDate),
            makeStatus("com.example.B", state: .checking),
            makeStatus("com.example.C", state: .skipped(untilVersion: "2.0")),
        ]
        #expect(AppUpdateStatus.newlyOutdated(in: current, comparedTo: []).isEmpty)
    }
}
