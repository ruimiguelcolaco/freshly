import Foundation
import UserNotifications
import FreshlyModels

/// Posts a local notification when scheduled checks find new updates.
/// Only automatic checks notify — the user is already looking during a
/// manual refresh.
enum NotificationManager {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notifyNewUpdates") as? Bool ?? true
    }

    static func notifyNewUpdates(_ fresh: [AppUpdateStatus]) {
        guard isEnabled, !fresh.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            if fresh.count == 1,
               let status = fresh.first,
               case .outdated(let best, _) = status.state {
                content.title = String(localized: "Update available")
                content.body = String(localized: "\(status.app.name) \(best.version.rawValue) is available")
            } else {
                content.title = String(localized: "Updates available")
                content.body = String(localized: "\(fresh.count) apps have updates")
            }

            // A stable identifier replaces the previous notification
            // instead of stacking one per check.
            center.add(UNNotificationRequest(
                identifier: "freshly-new-updates",
                content: content,
                trigger: nil
            ))
        }
    }
}
