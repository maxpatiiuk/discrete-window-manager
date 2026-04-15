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
            self.setupHotKeys()
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
        for hk in hotKeys { hk.stop() }
        hotKeys.removeAll()

        let monitorCount = monitorStateStore.monitors.count
        let mods = Configuration.HotKeys.modifiers
        let moveMods = Configuration.HotKeys.moveModifiers

        // Global Actions
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.status, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleStatusIndicator() }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.debug, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleDebugIndicator() }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.managedToggle, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.toggleFocusedWorkspaceManaged() }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.moveLeft, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.moveActiveWorkspace(direction: -1) }
        })
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.moveRight, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.moveActiveWorkspace(direction: 1) }
        })

        // Left Screen Workspaces
        for (i, key) in Configuration.HotKeys.leftScreenKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: mods) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: 0, index: i) }
            })
        }
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.leftScreenCycle, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.cycleWorkspace(screen: 0) }
        })

        // Middle Screen Workspaces
        let middleScreenIndex = monitorCount > 2 ? 1 : 0
        let middleWSOffset = monitorCount > 2 ? 0 : Configuration.HotKeys.leftScreenKeys.count
        for (i, key) in Configuration.HotKeys.middleScreenKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: mods) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: middleScreenIndex, index: middleWSOffset + i) }
            })
        }
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.middleScreenCycle, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.cycleWorkspace(screen: middleScreenIndex) }
        })

        // Right Screen Workspaces
        let rightScreenIndex = monitorCount > 1 ? (monitorCount - 1) : 0
        let rightWSOffset = monitorCount > 1 ? 0 : (middleWSOffset + Configuration.HotKeys.middleScreenKeys.count)
        for (i, key) in Configuration.HotKeys.rightScreenKeys.enumerated() {
            hotKeys.append(GlobalHotKeyMonitor(key: key, modifiers: mods) { [weak self] in
                Task { @MainActor [weak self] in self?.switchToWorkspace(screen: rightScreenIndex, index: rightWSOffset + i) }
            })
        }
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.rightScreenCycle, modifiers: mods) { [weak self] in
            Task { @MainActor [weak self] in self?.cycleWorkspace(screen: rightScreenIndex) }
        })

        // Window Movement (Move to Screen)
        hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.leftScreenKeys[0], modifiers: moveMods) { [weak self] in
            Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(0) }
        })
        if monitorCount > 2 {
            hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.middleScreenKeys[0], modifiers: moveMods) { [weak self] in
                Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(1) }
            })
        }
        if monitorCount > 1 {
            hotKeys.append(GlobalHotKeyMonitor(key: Configuration.HotKeys.rightScreenKeys[0], modifiers: moveMods) { [weak self] in
                Task { @MainActor [weak self] in self?.moveFocusedWindowToScreen(monitorCount - 1) }
            })
        }

        for hk in hotKeys { hk.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hk in hotKeys { hk.stop() }
        monitorStateStore.stopWatching()
        windowStateStore.stopWatching()
    }

    private func switchToWorkspace(screen: Int, index: Int) {
        workspaceManager.switchToWorkspace(screenIndex: screen, workspaceIndex: index, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true, forceCapture: true)
    }

    private func cycleWorkspace(screen: Int) {
        workspaceManager.cycleWorkspace(screenIndex: screen, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true, forceCapture: true)
    }

    private func moveActiveWorkspace(direction: Int) {
        workspaceManager.moveActiveWorkspace(direction: direction, windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        reconcileAndActuate(forceCapture: true)
    }

    private func moveFocusedWindowToScreen(_ screen: Int) {
        workspaceManager.moveFocusedWindowToScreen(screenIndex: screen, windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        reconcileAndActuate(warpMouse: true, forceCapture: true)
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
        let result = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        guard let focused = windowStateStore.windows.first(where: { $0.isFocused }),
              let wsID = result.screenWorkspaces.flatMap({ $0.workspaces }).first(where: { $0.windowIDs.contains(focused.windowNumber) })?.id else { return }

        workspaceManager.toggleManaged(workspaceID: wsID)
        reconcileAndActuate(forceCapture: true)
        
        let newResult = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors)
        indicatorController.show(textsByScreenID: statusTextsByResult(newResult), duration: 1.5)
    }

    private func reconcileAndActuate(warpMouse: Bool = false, forceCapture: Bool = false) {
        let result = workspaceManager.reconcile(windows: windowStateStore.windows, monitors: monitorStateStore.monitors, forceCapture: forceCapture)
        actuator.apply(layouts: result.layouts)
        if warpMouse, let targetWinID = result.targetFocusWindowNumber {
            warpMouseToFocusedWindow(targetWinID, layouts: result.layouts)
        }
        if indicatorController.isVisible {
            indicatorController.updateIfVisible(textsByScreenID: statusTextsByResult(result))
        }
    }

    private func warpMouseToFocusedWindow(_ windowID: Int, layouts: [WorkspaceManager.WindowLayout]) {
        guard let layout = layouts.first(where: { $0.windowNumber == windowID }) else { return }
        let center = CGPoint(x: layout.frame.midX, y: layout.frame.midY)
        AXWindowUtility.shared.warpMouse(to: center)
        AXWindowUtility.shared.focusWindow(windowID: windowID, pid: layout.ownerPID)
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
