import Foundation
import Testing
import FreshlyModels
@testable import FreshlyEngine

@Suite("UpdateCheckReport")
struct UpdateCheckReportTests {
    private func app(_ bundleID: String, version: AppVersion = "1.0") -> InstalledApp {
        InstalledApp(
            bundleID: bundleID,
            name: bundleID,
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            version: version
        )
    }

    @Test("Summarizes final states and ignores transient checking emissions")
    func summarizesStates() {
        let report = UpdateCheckReport(statuses: [
            AppUpdateStatus(app: app("com.example.Checking"), state: .checking),
            AppUpdateStatus(app: app("com.example.Current"), state: .upToDate),
            AppUpdateStatus(app: app("com.example.Unsupported"), state: .unsupported),
            AppUpdateStatus(
                app: app("com.example.Update", version: "1.0"),
                state: .outdated(
                    best: ReleaseInfo(version: "2.0", source: .homebrew),
                    alternatives: []
                )
            ),
            AppUpdateStatus(
                app: app("com.example.Failed"),
                state: .failed(UpdateError(.sourceRateLimited(.github)))
            ),
        ], checkedAt: Date(timeIntervalSince1970: 0))

        #expect(report.schemaVersion == 1)
        #expect(report.checkedApps == 4)
        #expect(report.unsupportedApps == 1)
        #expect(report.updates.count == 1)
        #expect(report.updates[0].installedVersion == "1.0")
        #expect(report.updates[0].availableVersion == "2.0")
        #expect(report.updates[0].source == .homebrew)
        #expect(report.failures.count == 1)
        #expect(report.failures[0].code == .rateLimited)
    }

    @Test("Array order is stable across discovery order")
    func stableOrder() {
        func outdated(_ bundleID: String) -> AppUpdateStatus {
            AppUpdateStatus(
                app: app(bundleID),
                state: .outdated(
                    best: ReleaseInfo(version: "2.0", source: .sparkle),
                    alternatives: []
                )
            )
        }
        let report = UpdateCheckReport(statuses: [
            outdated("com.example.Zeta"),
            outdated("com.example.Alpha"),
        ])
        #expect(report.updates.map(\.bundleID) == ["com.example.Alpha", "com.example.Zeta"])
    }

    @Test("JSON contract uses an ISO date and string source identifiers")
    func jsonContract() throws {
        let report = UpdateCheckReport(
            statuses: [
                AppUpdateStatus(
                    app: app("com.example.App"),
                    state: .outdated(
                        best: ReleaseInfo(version: "2.0", source: .github),
                        alternatives: []
                    )
                ),
            ],
            checkedAt: Date(timeIntervalSince1970: 0)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updates = try #require(object["updates"] as? [[String: Any]])

        #expect(Set(object.keys) == [
            "schemaVersion", "checkedAt", "checkedApps", "unsupportedApps", "updates", "failures",
        ])
        #expect(object["checkedAt"] as? String == "1970-01-01T00:00:00Z")
        #expect(updates.first?["source"] as? String == "github")
    }
}
