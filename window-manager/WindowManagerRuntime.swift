//
// Coordinates app lifecycle startup tasks: accessory mode, login registration, hotkey wiring, and permission flow.

import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let indicatorController = IndicatorWindowController()
    private let loginItemRegistrar = LoginItemRegistrar()
    private let monitorStateStore = MonitorStateStore()
    private let windowStateStore = WindowStateStore()
    private let workspaceManager = WorkspaceManager()
    private var statusHotKey: GlobalHotKeyMonitor?
    private var debugHotKey: GlobalHotKeyMonitor?
    private var managedHotKey: GlobalHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("App launched")
        loginItemRegistrar.registerIfNeeded()

        monitorStateStore.onMonitorsChanged = { [weak self] in
            guard let self else {
                return
            }

            self.windowStateStore.refresh()
            self.reconcileAndActuate()
        }

        windowStateStore.onWindowsChanged = { [weak self] in
            guard let self else {
                return
            }

            self.reconcileAndActuate()
        }

        monitorStateStore.startWatching()
        windowStateStore.startWatching()

        statusHotKey = GlobalHotKeyMonitor(key: "s", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleStatusIndicator()
            }
        }
        statusHotKey?.start()

        debugHotKey = GlobalHotKeyMonitor(key: "d", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleDebugIndicator()
            }
        }
        debugHotKey?.start()

        managedHotKey = GlobalHotKeyMonitor(key: "m", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleFocusedWorkspaceManaged()
            }
        }
        managedHotKey?.start()

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
        statusHotKey?.stop()
        debugHotKey?.stop()
        managedHotKey?.stop()
        monitorStateStore.onMonitorsChanged = nil
        windowStateStore.onWindowsChanged = nil
        monitorStateStore.stopWatching()
        windowStateStore.stopWatching()
    }

    @MainActor
    private func toggleStatusIndicator() {
        guard AccessibilityPermissionManager.shared.isAccessibilityGranted() else {
            indicatorController.show(text: "Enable Accessibility permission")
            return
        }

        let result = workspaceManager.reconcile(
            windows: windowStateStore.windows,
            monitors: monitorStateStore.monitors
        )
        
        indicatorController.toggle(textsByScreenID: statusTextsByResult(result))
    }

    @MainActor
    private func toggleDebugIndicator() {
        indicatorController.toggle(textsByScreenID: debugTextsByScreen())
    }

    @MainActor
    private func toggleFocusedWorkspaceManaged() {
        guard let focused = windowStateStore.windows.first(where: { $0.isFocused }) else {
            return
        }

        let result = workspaceManager.reconcile(
            windows: windowStateStore.windows,
            monitors: monitorStateStore.monitors
        )
        
        if let screen = result.screenWorkspaces.first(where: { sw in sw.workspaces.contains(where: { $0.id == sw.activeWorkspaceID }) && sw.workspaces.first(where: { $0.id == sw.activeWorkspaceID })?.windowIDs.contains(focused.windowNumber) == true }),
           let wsID = screen.activeWorkspaceID {
            workspaceManager.toggleManaged(workspaceID: wsID)
            
            // Force reconcile and show update
            let newResult = workspaceManager.reconcile(
                windows: windowStateStore.windows,
                monitors: monitorStateStore.monitors
            )
            actuateLayouts(newResult.layouts)
            indicatorController.show(textsByScreenID: statusTextsByResult(newResult), duration: 1.5)
        }
    }

    private func reconcileAndActuate() {
        let result = workspaceManager.reconcile(
            windows: windowStateStore.windows,
            monitors: monitorStateStore.monitors
        )

        actuateLayouts(result.layouts)

        if indicatorController.isVisible {
            indicatorController.updateIfVisible(textsByScreenID: statusTextsByResult(result))
        }
    }

    private func actuateLayouts(_ layouts: [WorkspaceManager.WindowLayout]) {
        for layout in layouts {
            actuate(layout: layout)
        }
    }

    private func actuate(layout: WorkspaceManager.WindowLayout) {
        // This is a placeholder for the actual AX move/resize logic
        if layout.isHidden {
            AppLog.debug("HIDE window \(layout.windowNumber)", logger: AppLog.windowState)
        } else {
            AppLog.debug("SHOW/MOVE window \(layout.windowNumber) to \(layout.frame)", logger: AppLog.windowState)
        }
    }

    private func statusTextsByResult(_ result: WorkspaceManager.ReconciliationResult) -> [String: String] {
        return result.screenWorkspaces.reduce(into: [String: String]()) { acc, screen in
            acc[screen.screenID] = workspaceManager.getStatusText(for: screen, windows: windowStateStore.windows)
        }
    }

    private func debugTextsByScreen() -> [String: String] {
        let text = "\(monitorStateStore.debugText())\n\n\(windowStateStore.debugText())"
        return monitorStateStore.monitors.reduce(into: [String: String]()) { acc, monitor in
            acc[monitor.id] = text
        }
    }
}
