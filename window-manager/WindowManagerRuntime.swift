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
    private let actuator = Actuator()
    
    private var hotKeys: [GlobalHotKeyMonitor] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("App launched")
        loginItemRegistrar.registerIfNeeded()

        monitorStateStore.onMonitorsChanged = { [weak self] in
            guard let self else { return }
            self.windowStateStore.currentMonitors = self.monitorStateStore.monitors
            self.windowStateStore.refresh()
            self.reconcileAndActuate()
        }

        windowStateStore.onWindowsChanged = { [weak self] in
            guard let self else { return }
            self.reconcileAndActuate()
        }

        windowStateStore.currentMonitors = monitorStateStore.monitors
        monitorStateStore.startWatching()
        windowStateStore.startWatching()

        setupHotKeys()

        let hasAccessibility = AccessibilityPermissionManager.shared.requestAccessibilityPermission(prompt: true)
        if hasAccessibility {
            indicatorController.show(text: "Window manager ready")
        } else {
            indicatorController.show(text: "Enable Accessibility permission")
        }
    }

    private func setupHotKeys() {
        // Core toggles
        hotKeys.append(GlobalHotKeyMonitor(key: "s", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleStatusIndicator() }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: "d", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleDebugIndicator() }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: "m", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleFocusedWorkspaceManaged() }
        })

        // Workspace Keys
        // Left screen: alt+z,x,c,v,b
        let leftKeys = ["z", "x", "c", "v"]
        for (i, key) in leftKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: [.option]) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: 0, index: i) }
            })
        }
        hotKeys.append(GlobalHotKeyMonitor(key: "b", modifiers: [.option]) { [weak self] in
            Task { @MainActor [weak self] in self?.cycleWorkspace(screen: 0) }
        })

        // Middle screen: alt+q,w,e,r,t
        let middleKeys = ["q", "w", "e", "r", "t"]
        for (i, key) in middleKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: [.option]) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: 1, index: i) }
            })
        }

        // Right screen: alt+n,m,,,.,0
        let rightKeys = ["n", "m", ",", ".", "0"]
        for (i, key) in rightKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: [.option]) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: 2, index: i) }
            })
        }

        // Movement Keys (Shift + Screen Base Key)
        hotKeys.append(GlobalHotKeyMonitor(key: "z", modifiers: [.option, .shift]) { [weak self] in
            Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(0) }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: "q", modifiers: [.option, .shift]) { [weak self] in
            Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(1) }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: "n", modifiers: [.option, .shift]) { [weak self] in
            Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(2) }
        })

        for hk in hotKeys { hk.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hk in hotKeys { hk.stop() }
        monitorStateStore.stopWatching()
        windowStateStore.stopWatching()
    }

    private func switchToWorkspace(screen: Int, index: Int) {
        workspaceManager.switchToWorkspace(screenIndex: screen, workspaceIndex: index, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true)
    }

    private func cycleWorkspace(screen: Int) {
        workspaceManager.cycleWorkspace(screenIndex: screen, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true)
    }

    private func moveFocusedWindowToScreen(_ screen: Int) {
        workspaceManager.moveFocusedWindowToScreen(screenIndex: screen, windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true)
    }

    @MainActor
    private func toggleStatusIndicator() {
        if indicatorController.isVisible {
            indicatorController.hide()
        } else {
            let result = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
            indicatorController.show(textsByScreenID: statusTextsByResult(result), duration: nil)
        }
    }

    @MainActor
    private func toggleDebugIndicator() {
        indicatorController.toggle(textsByScreenID: debugTextsByScreen())
    }

    @MainActor
    private func toggleFocusedWorkspaceManaged() {
        guard let focused = windowStateStore.windows.first(where: { $0.isFocused }),
              let wsID = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors).screenWorkspaces
                .flatMap({ $0.workspaces })
                .first(where: { $0.windowIDs.contains(focused.windowNumber) })?.id else { return }

        workspaceManager.toggleManaged(workspaceID: wsID)
        reconcileAndActuate()
        
        let newResult = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        indicatorController.show(textsByScreenID: statusTextsByResult(newResult), duration: 1.5)
    }

    private func reconcileAndActuate(warpMouse: Bool = false) {
        let result = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        
        actuator.apply(layouts: result.layouts)

        if warpMouse {
            warpMouseToFocusedWindow(result.layouts)
        }

        if indicatorController.isVisible {
            indicatorController.updateIfVisible(textsByScreenID: statusTextsByResult(result))
        }
    }

    private func warpMouseToFocusedWindow(_ layouts: [WorkspaceManager.WindowLayout]) {
        let visibleWindows = layouts.filter { !$0.isHidden }
        if let focused = visibleWindows.first(where: { $0.isFocused }) {
            let center = CGPoint(x: focused.frame.midX, y: focused.frame.midY)
            AXWindowUtility.shared.warpMouse(to: center)
            AXWindowUtility.shared.focusWindow(windowID: focused.windowNumber, pid: focused.ownerPID)
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
