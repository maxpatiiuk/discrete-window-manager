//
// Coordinates app lifecycle startup tasks: accessory mode, login registration, hotkey wiring, and permission flow.

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let indicatorController = IndicatorWindowController()
    private let loginItemRegistrar = LoginItemRegistrar()
    private let monitorStateStore = MonitorStateStore()
    private var hotKeyMonitor: GlobalHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("App launched")
        loginItemRegistrar.registerIfNeeded()

        monitorStateStore.onMonitorsChanged = { [weak self] in
            guard let self else {
                return
            }

            self.indicatorController.updateIfVisible(text: self.monitorStateStore.debugText())
        }

        monitorStateStore.startWatching()

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
        monitorStateStore.stopWatching()
    }

    @MainActor
    private func toggleIndicatorFromHotKey() {
        guard AccessibilityPermissionManager.shared.isAccessibilityGranted() else {
            AppLog.error("Ignoring hotkey because Accessibility permission is missing", logger: AppLog.hotKey)
            indicatorController.show(text: "Enable Accessibility permission")
            return
        }

        indicatorController.toggle(text: monitorStateStore.debugText())
    }
}
