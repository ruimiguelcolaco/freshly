import Foundation
import FreshlyModels

public enum IndividualUpdatePlan: Sendable, Equatable {
    case ignored
    case handOff(URL)
    case confirmQuit
    case install
}

public struct BatchUpdatePlan: Sendable, Equatable {
    public let installable: [AppUpdateStatus]
    public let running: [AppUpdateStatus]
    public let handOffToAppStore: Bool
}

/// Pure routing decisions for update requests. The app executes URL hand-offs,
/// consent UI, and installer tasks after this policy returns.
public enum UpdateRequestPlanning {
    public static func individual(
        _ status: AppUpdateStatus,
        hasPendingConfirmation: Bool,
        isInstalling: Bool,
        isRunning: Bool
    ) -> IndividualUpdatePlan {
        guard !hasPendingConfirmation,
              !isInstalling,
              case .outdated(let release, _) = status.state else {
            return .ignored
        }
        if release.source == .macAppStore, release.downloadURL == nil {
            return .handOff(appStoreURL(for: release))
        }
        if release.downloadURL == nil, let page = release.releaseNotesURL {
            return .handOff(page)
        }
        return isRunning ? .confirmQuit : .install
    }

    public static func batch(
        _ outdated: [AppUpdateStatus],
        installing: Set<URL>,
        isRunning: (InstalledApp) -> Bool
    ) -> BatchUpdatePlan {
        let targets = outdated.filter { !installing.contains($0.id) }
        var installable: [AppUpdateStatus] = []
        var handOffToAppStore = false
        for target in targets {
            guard case .outdated(let release, _) = target.state else { continue }
            if release.source == .macAppStore, release.downloadURL == nil {
                handOffToAppStore = true
            } else {
                installable.append(target)
            }
        }
        return BatchUpdatePlan(
            installable: installable,
            running: installable.filter { isRunning($0.app) },
            handOffToAppStore: handOffToAppStore
        )
    }

    private static func appStoreURL(for release: ReleaseInfo) -> URL {
        if let page = release.releaseNotesURL,
           var components = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            components.scheme = "macappstore"
            if let url = components.url { return url }
        }
        return URL(string: "macappstore://showUpdatesPage")!
    }
}
