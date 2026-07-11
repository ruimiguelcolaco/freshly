import Foundation
import Observation
import ServiceManagement

/// Wraps `SMAppService` so Settings can toggle "launch at login" and show
/// the real registration state (macOS may deny or require approval).
@Observable
@MainActor
final class LoginItemModel {
    private(set) var isEnabled: Bool
    private(set) var lastError: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
