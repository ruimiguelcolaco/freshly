import Foundation
import Testing
import FreshlyEngine
import FreshlyModels

@Suite("AppStatusSections")
struct AppStatusSectionsTests {
    private func app(_ name: String) -> InstalledApp {
        InstalledApp(
            bundleID: "com.example.\(name)",
            name: name,
            path: URL(filePath: "/Applications/\(name).app"),
            version: "1.0"
        )
    }

    private func release(_ version: AppVersion, source: SourceID) -> ReleaseInfo {
        ReleaseInfo(version: version, source: source)
    }

    @Test("Each status is classified once and each section is name-sorted")
    func classifiesAndSorts() {
        let statuses = [
            AppUpdateStatus(app: app("Zulu"), state: .checking),
            AppUpdateStatus(app: app("Beta"), state: .upToDate),
            AppUpdateStatus(app: app("Alpha"), state: .upToDate),
            AppUpdateStatus(app: app("Unsupported"), state: .unsupported),
            AppUpdateStatus(app: app("Failed"), state: .failed(UpdateError(.underlying(detail: "test")))),
            AppUpdateStatus(
                app: app("Update"),
                state: .outdated(best: release("2.0", source: .sparkle), alternatives: [])
            ),
        ]

        let sections = AppStatusSections.classify(
            statuses,
            preferredSource: { _ in nil },
            skippedVersion: { _ in nil }
        )

        #expect(sections.outdated.map(\.app.name) == ["Update"])
        #expect(sections.checking.map(\.app.name) == ["Zulu"])
        #expect(sections.upToDate.map(\.app.name) == ["Alpha", "Beta"])
        #expect(sections.notCheckable.map(\.app.name) == ["Failed", "Unsupported"])
        #expect(sections.skipped.isEmpty)
    }

    @Test("A source override is applied before its selected version is skipped")
    func overrideBeforeSkip() {
        let installed = app("Channels")
        let status = AppUpdateStatus(
            app: installed,
            state: .outdated(
                best: release("3.0", source: .sparkle),
                alternatives: [release("2.0", source: .github)]
            )
        )

        let sections = AppStatusSections.classify(
            [status],
            preferredSource: { _ in .github },
            skippedVersion: { _ in "2.0" }
        )

        #expect(sections.outdated.isEmpty)
        #expect(sections.skipped.count == 1)
        #expect(sections.skipped[0].state == .skipped(untilVersion: "2.0"))
    }
}
