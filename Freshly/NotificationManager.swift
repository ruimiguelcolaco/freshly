import Foundation
import UserNotifications
import FreshlyModels

/// Posts a local notification when scheduled checks find new updates.
/// Only automatic checks notify — the user is already looking during a
/// manual refresh.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let singleCategoryID = "freshly-single-update"
    private nonisolated static let multipleCategoryID = "freshly-multiple-updates"
    private nonisolated static let updateAppActionID = "freshly-update-app"
    private nonisolated static let updateAllActionID = "freshly-update-all"
    private nonisolated static let appPathKey = "freshly-app-path"

    private let center: UNUserNotificationCenter
    var actionHandler: ((NotificationAction) -> Void)?

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notifyNewUpdates") as? Bool ?? true
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        registerCategories()
    }

    func notifyNewUpdates(_ fresh: [AppUpdateStatus]) {
        guard isEnabled, !fresh.isEmpty else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .badge])) == true else {
                return
            }

            let content = UNMutableNotificationContent()
            if fresh.count == 1,
               let status = fresh.first,
               case .outdated(let best, _) = status.state {
                content.title = String(localized: "Update available")
                content.body = String(localized: "\(status.app.name) \(best.version.rawValue) is available")
                content.categoryIdentifier = Self.singleCategoryID
                content.userInfo = [Self.appPathKey: status.app.path.path]
            } else {
                content.title = String(localized: "Updates available")
                content.body = String(localized: "\(fresh.count) apps have updates")
                content.categoryIdentifier = Self.multipleCategoryID
            }

            // A stable identifier replaces the previous notification
            // instead of stacking one per check.
            try? await center.add(UNNotificationRequest(
                identifier: "freshly-new-updates",
                content: content,
                trigger: nil
            ))
        }
    }

    private func registerCategories() {
        let updateApp = UNNotificationAction(
            identifier: Self.updateAppActionID,
            title: String(localized: "Update Now"),
            options: [.foreground]
        )
        let updateAll = UNNotificationAction(
            identifier: Self.updateAllActionID,
            title: String(localized: "Update All"),
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.singleCategoryID,
                actions: [updateApp],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Self.multipleCategoryID,
                actions: [updateAll],
                intentIdentifiers: []
            ),
        ])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = Self.action(from: response)
        completionHandler()
        Task { @MainActor [weak self] in
            if let action {
                self?.actionHandler?(action)
            }
        }
    }

    nonisolated private static func action(from response: UNNotificationResponse) -> NotificationAction? {
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            .openFreshly
        case Self.updateAppActionID:
            if let path = response.notification.request.content.userInfo[Self.appPathKey] as? String {
                .updateApp(path: path)
            } else {
                .openFreshly
            }
        case Self.updateAllActionID:
            .updateAll
        default:
            nil
        }
    }
}
