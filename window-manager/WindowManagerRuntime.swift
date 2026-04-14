//
// Coordinates app lifecycle startup tasks: accessory mode, login registration, hotkey wiring, and permission flow.

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let indicatorController = IndicatorWindowController()
    private let loginItemRegistrar = LoginItemRegistrar()
    private let monitorStateStore = MonitorStateStore()
    private let windowStateStore = WindowStateStore()
    private var hotKeyMonitor: GlobalHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("App launched")
        loginItemRegistrar.registerIfNeeded()

        monitorStateStore.onMonitorsChanged = { [weak self] in
            guard let self else {
                return
            }

            self.windowStateStore.refresh()
            self.indicatorController.updateIfVisible(text: self.statusDialogText())
        }

        windowStateStore.onWindowsChanged = { [weak self] in
            guard let self else {
                return
            }

            self.indicatorController.updateIfVisible(text: self.statusDialogText())
        }

        monitorStateStore.startWatching()
        windowStateStore.startWatching()

        hotKeyMonitor = GlobalHotKeyMonitor(key: "s", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleIndicatorFromHotKey()
            }
        }
        hotKeyMonitor?.start()

        let hasAccessibility = AccessibilityPermissionManager.shared
            .requestAccessibilityPermission(prompt: true)

        if hasAccessibility {
            AppLog.debug("Accessibility permission is granted", logger: AppLog.accessibility)
            indicatorController.show(text: "Window manager ready")
        } else {
            AppLog.error("Accessibility permission is missing", logger: AppLog.accessibility)
            indicatorController.show(text: "Enable Accessibility permission")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        monitorStateStore.onMonitorsChanged = nil
        windowStateStore.onWindowsChanged = nil
        monitorStateStore.stopWatching()
        windowStateStore.stopWatching()
    }

    @MainActor
    private func toggleIndicatorFromHotKey() {
        guard AccessibilityPermissionManager.shared.isAccessibilityGranted() else {
            AppLog.error("Ignoring hotkey because Accessibility permission is missing", logger: AppLog.hotKey)
            indicatorController.show(text: "Enable Accessibility permission")
            return
        }

        indicatorController.toggle(text: statusDialogText())
    }

    private func statusDialogText() -> String {
        "\(monitorStateStore.debugText())\n\n\(windowStateStore.debugText())"
    }
}
