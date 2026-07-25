import AppKit

/// Keeps Freshly living in the menu bar independently of its windows:
/// the Dock icon exists while a window is open (unless the user turned
/// it off in Settings) and disappears with the last one, and quitting
/// from the Dock or ⌘Q just retreats to the menu bar. Only the menu
/// bar's own Quit item — or a system logout, restart, or shutdown —
/// actually terminates the app.
final class FreshlyAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the menu bar's Quit item right before it calls
    /// `terminate` — the one quit request that is obeyed.
    static var quitRequested = false

    /// The Settings toggle. Off means Freshly is menu-bar-only, windows
    /// or not.
    static var showsDockIcon: Bool {
        UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    }

    /// Recomputes the activation policy from the preference and the
    /// windows currently on screen. Called when the toggle changes.
    static func applyDockIconPreference() {
        if showsDockIcon {
            let hasWindow = NSApp.windows.contains { $0.isVisible && isRegularWindow($0) }
            NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        // Keep the window the user is interacting with in front — policy
        // switches deactivate the app.
        NSApp.activate()
    }

    /// Brings the single SwiftUI main window forward after a notification
    /// action needs confirmation or the notification itself is opened.
    static func showMainWindow() {
        if showsDockIcon, NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first {
            $0.title == "Freshly" && isRegularWindow($0)
        }?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FreshlyAppDelegate.applyDockIconPreference()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitRequested || Self.isSystemInitiatedQuit() {
            return .terminateNow
        }
        // Retreat to the menu bar instead of dying: close the windows,
        // drop the Dock icon, keep checking for updates.
        for window in sender.windows where window.isVisible && Self.isRegularWindow(window) {
            window.close()
        }
        sender.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    /// A logout, restart, or shutdown sends the quit Apple event with a
    /// `why?` reason attached; a user quit (Dock, ⌘Q, scripts) does not.
    /// Blocking those would hold up the whole system.
    private static func isSystemInitiatedQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        let quitReason = "why?".utf8.reduce(AEKeyword(0)) { ($0 << 8) | AEKeyword($1) }
        return event.attributeDescriptor(forKeyword: quitReason) != nil
    }

    /// The windows that should keep a Dock icon alive — not the status
    /// item's own window, not popovers and other panels.
    private static func isRegularWindow(_ window: NSWindow) -> Bool {
        window.canBecomeKey
            && !(window is NSPanel)
            && !NSStringFromClass(type(of: window)).contains("StatusBar")
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isRegularWindow(window) else {
            return
        }
        if Self.showsDockIcon, NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        // A menu-bar app launches as .accessory, so its window opens behind
        // whatever is frontmost and the cooperative `activate()` won't pull it
        // up. Force the app and this window forward — the deprecated variant is
        // the one that reliably steals focus on a user-initiated launch/open.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, Self.isRegularWindow(closing) else {
            return
        }
        // The closing window is still on screen here; decide on the next
        // runloop turn, when it is gone.
        Task { @MainActor in
            let anyWindowLeft = NSApp.windows.contains {
                $0.isVisible && $0 != closing && Self.isRegularWindow($0)
            }
            if !anyWindowLeft {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
