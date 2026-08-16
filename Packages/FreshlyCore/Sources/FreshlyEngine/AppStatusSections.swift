import Foundation
import FreshlyModels

/// The display projection consumed by the app. Classification is deliberately
/// a core policy: source overrides are applied before skips, every status is
/// classified exactly once, and each section is sorted independently.
public struct AppStatusSections: Sendable, Equatable {
    public var outdated: [AppUpdateStatus] = []
    public var checking: [AppUpdateStatus] = []
    public var upToDate: [AppUpdateStatus] = []
    public var skipped: [AppUpdateStatus] = []
    public var notCheckable: [AppUpdateStatus] = []

    public static func classify(
        _ statuses: some Sequence<AppUpdateStatus>,
        preferredSource: (String) -> SourceID?,
        skippedVersion: (String) -> AppVersion?
    ) -> AppStatusSections {
        var sections = AppStatusSections()

        for raw in statuses {
            var status = raw.preferring(preferredSource(raw.app.bundleID))
            if case .outdated(let best, _) = status.state,
               skippedVersion(status.app.bundleID) == best.version {
                status.state = .skipped(untilVersion: best.version)
            }

            switch status.state {
            case .outdated:
                sections.outdated.append(status)
            case .checking:
                sections.checking.append(status)
            case .upToDate:
                sections.upToDate.append(status)
            case .skipped:
                sections.skipped.append(status)
            case .unsupported, .failed:
                sections.notCheckable.append(status)
            }
        }

        func sort(_ statuses: inout [AppUpdateStatus]) {
            statuses.sort {
                $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
            }
        }
        sort(&sections.outdated)
        sort(&sections.checking)
        sort(&sections.upToDate)
        sort(&sections.skipped)
        sort(&sections.notCheckable)
        return sections
    }
}
