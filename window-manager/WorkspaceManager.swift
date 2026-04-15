import AppKit
import Foundation

@MainActor
final class WorkspaceManager {
    struct ManagedApp {
        let bundleID: String
    }

    struct Workspace: Equatable {
        let id: Int
        var windowIDs: Set<Int>
        var isManaged: Bool
    }

    struct WindowLayout {
        let windowNumber: Int
        let ownerPID: pid_t
        let frame: NSRect
        let isHidden: Bool
        let isFocused: Bool
        let currentMonitorID: String?
    }

    struct ReconciliationResult {
        let layouts: [WindowLayout]
        let screenWorkspaces: [ScreenWorkspaces]
        let targetFocusWindowNumber: Int?
    }

    struct ScreenWorkspaces {
        let screenID: String
        let screenName: String
        let workspaces: [Workspace]
        let activeWorkspaceID: Int?
    }

    private let managedAppBundleIDs = Configuration.managedAppBundleIDs

    private func isManagedApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return managedAppBundleIDs.contains(bundleID)
    }

    // Persistent state
    private var workspaces: [Int: Workspace] = [:]
    private var windowToWorkspace: [Int: Int] = [:] 
    private var windowToPID: [Int: pid_t] = [:] 
    private var workspaceToScreen: [Int: String] = [:] 
    private var screenToWorkspaceOrder: [String: [Int]] = [:] 
    private var activeWorkspacePerScreen: [String: Int] = [:] 
    private var previousActiveWorkspacePerScreen: [String: Int] = [:] 
    private var windowToLastDisplayID: [Int: String] = [:] 
    private var windowToLastRect: [Int: NSRect] = [:] 
    private var disconnectedDisplayIDs: Set<String> = []
    
    private var nextWorkspaceID = 1
    private var lastManualSwitchTime: Date?
    private var lastSwitchedScreenID: String?
    private var isFirstReconciliation = true

    func toggleManaged(workspaceID: Int) {
        if var ws = workspaces[workspaceID] {
            ws.isManaged.toggle()
            workspaces[workspaceID] = ws
        }
    }

    func isWorkspaceManaged(id: Int) -> Bool {
        return workspaces[id]?.isManaged ?? false
    }

    func switchToWorkspace(screenIndex: Int, workspaceIndex: Int, monitors: [MonitorStateStore.MonitorSnapshot]) {
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { return }
        let monitor = sortedMonitors[screenIndex]
        let order = screenToWorkspaceOrder[monitor.id] ?? []
        guard !order.isEmpty else { return }
        let targetIndex = min(workspaceIndex, order.count - 1)
        if let current = activeWorkspacePerScreen[monitor.id] { previousActiveWorkspacePerScreen[monitor.id] = current }
        activeWorkspacePerScreen[monitor.id] = order[targetIndex]
        lastManualSwitchTime = Date()
        lastSwitchedScreenID = monitor.id
    }

    func cycleWorkspace(screenIndex: Int, monitors: [MonitorStateStore.MonitorSnapshot]) {
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { return }
        let monitor = sortedMonitors[screenIndex]
        let order = screenToWorkspaceOrder[monitor.id] ?? []
        guard !order.isEmpty else { return }
        let currentWSID = activeWorkspacePerScreen[monitor.id] ?? order[0]
        if let currentIndex = order.firstIndex(of: currentWSID) {
            let nextIndex = (currentIndex + 1) % order.count
            previousActiveWorkspacePerScreen[monitor.id] = currentWSID
            activeWorkspacePerScreen[monitor.id] = order[nextIndex]
            lastManualSwitchTime = Date()
            lastSwitchedScreenID = monitor.id
        }
    }

    func moveActiveWorkspace(direction: Int, windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        guard let focusedWindow = windows.first(where: { $0.isFocused }),
              let activeWSID = windowToWorkspace[focusedWindow.windowNumber],
              let screenID = workspaceToScreen[activeWSID] else { return }
        guard var order = screenToWorkspaceOrder[screenID], let currentIndex = order.firstIndex(of: activeWSID) else { return }
        let newIndex = currentIndex + direction
        guard newIndex >= 0 && newIndex < order.count else { return }
        order.remove(at: currentIndex)
        order.insert(activeWSID, at: newIndex)
        screenToWorkspaceOrder[screenID] = order
    }

    func moveFocusedWindowToScreen(screenIndex: Int, windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        guard let focused = windows.first(where: { $0.isFocused }) else { return }
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { return }
        let targetMonitor = sortedMonitors[screenIndex]
        let winID = focused.windowNumber
        guard let oldWSID = windowToWorkspace[winID] else { return }
        let sourceScreenID = workspaceToScreen[oldWSID]
        if sourceScreenID != nil { previousActiveWorkspacePerScreen[sourceScreenID!] = oldWSID }
        if sourceScreenID == targetMonitor.id {
            let newWSID = createWorkspace(screenID: targetMonitor.id, isManaged: workspaces[oldWSID]?.isManaged ?? false)
            moveWindowToWorkspace(windowID: winID, from: oldWSID, to: newWSID)
            activeWorkspacePerScreen[targetMonitor.id] = newWSID
            windowToLastDisplayID[winID] = targetMonitor.id
            lastManualSwitchTime = Date()
            lastSwitchedScreenID = targetMonitor.id
            return
        }
        let isManaged = workspaces[oldWSID]?.isManaged ?? true
        let newWSID = createWorkspace(screenID: targetMonitor.id, isManaged: isManaged)
        moveWindowToWorkspace(windowID: winID, from: oldWSID, to: newWSID)
        activeWorkspacePerScreen[targetMonitor.id] = newWSID
        windowToLastDisplayID[winID] = targetMonitor.id
        if let sID = sourceScreenID {
            let order = screenToWorkspaceOrder[sID] ?? []
            if let first = order.first(where: { $0 != oldWSID && workspaces[$0] != nil }) { activeWorkspacePerScreen[sID] = first }
        }
        lastManualSwitchTime = Date()
        lastSwitchedScreenID = targetMonitor.id
    }

    private func moveWindowToWorkspace(windowID: Int, from oldWSID: Int, to newWSID: Int) {
        workspaces[oldWSID]?.windowIDs.remove(windowID)
        windowToWorkspace[windowID] = newWSID
        workspaces[newWSID]?.windowIDs.insert(windowID)
    }

    func captureCurrentWindowPositions(windows: [WindowStateStore.WindowSnapshot]) {
        for window in windows where abs(window.bounds.origin.x) < Configuration.visibleThreshold {
            windowToLastRect[window.windowNumber] = window.bounds
        }
    }

    func moveFocusedWindowToNewWorkspace(windowID: Int, screenID: String, isManaged: Bool) -> Int {
        let newWSID = createWorkspace(screenID: screenID, isManaged: isManaged)
        if let oldWSID = windowToWorkspace[windowID] {
            moveWindowToWorkspace(windowID: windowID, from: oldWSID, to: newWSID)
        }
        activeWorkspacePerScreen[screenID] = newWSID
        return newWSID
    }

    func reconcile(windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot], forceCapture: Bool = false) -> ReconciliationResult {
        // 1. Initial Position Capture (MUST run before assignment)
        if isFirstReconciliation {
            for window in windows where abs(window.bounds.origin.x) < Configuration.visibleThreshold {
                AppLog.debug("Initial capture for window \(window.windowNumber) (\(window.ownerName)): \(window.bounds)", logger: AppLog.windowState)
                windowToLastRect[window.windowNumber] = window.bounds
                if let actual = monitors.first(where: { $0.frame.contains(window.bounds.origin) }) {
                    windowToLastDisplayID[window.windowNumber] = actual.id
                }
            }
            isFirstReconciliation = false
        }

        // 2. Selective Capture for switches (requested by forceCapture)
        if forceCapture {
            for monitor in monitors {
                if let prevWSID = previousActiveWorkspacePerScreen[monitor.id], let activeWSID = activeWorkspacePerScreen[monitor.id],
                   prevWSID != activeWSID, let ws = workspaces[prevWSID], !ws.isManaged {
                    for winID in ws.windowIDs {
                        if let win = windows.first(where: { $0.windowNumber == winID }), abs(win.bounds.origin.x) < Configuration.visibleThreshold {
                            if let live = AXWindowUtility.shared.getWindowFrame(windowID: winID, pid: win.ownerPID) {
                                AppLog.debug("Live capture for unmanaged window \(winID) BEFORE switch: \(live)", logger: AppLog.windowState)
                                windowToLastRect[winID] = live
                            }
                        }
                    }
                }
            }
        }
        previousActiveWorkspacePerScreen.removeAll()

        assignWorkspacesToNewWindows(windows, monitors: monitors)
        updateActiveWorkspaces(windows, monitors: monitors)

        var layouts: [WindowLayout] = []
        var targetFocusWinID: Int?
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }

        if let switchedID = lastSwitchedScreenID, let activeWSID = activeWorkspacePerScreen[switchedID], let ws = workspaces[activeWSID] {
            targetFocusWinID = ws.windowIDs.first(where: { winID in windows.contains(where: { $0.windowNumber == winID }) })
        }

        for monitor in sortedMonitors {
            let activeWSID = activeWorkspacePerScreen[monitor.id]
            let order = screenToWorkspaceOrder[monitor.id] ?? []
            for wsID in order {
                guard let ws = workspaces[wsID] else { continue }
                let isWSActive = (wsID == activeWSID)
                for winID in ws.windowIDs {
                    guard let window = windows.first(where: { $0.windowNumber == winID }) else { continue }
                    let isVisibleNow = abs(window.bounds.origin.x) < Configuration.visibleThreshold

                    if isVisibleNow {
                        if let actual = monitors.first(where: { $0.frame.contains(window.bounds.origin) }) {
                            windowToLastDisplayID[winID] = actual.id
                        }
                    }

                    if isWSActive {
                        if targetFocusWinID == nil && window.isFocused { targetFocusWinID = winID }
                        let targetFrame: NSRect
                        if ws.isManaged { targetFrame = monitor.frame } else {
                            var orig = windowToLastRect[winID] ?? window.bounds
                            if abs(orig.origin.x) >= Configuration.visibleThreshold { orig = monitor.frame } // Fallback to fullscreen if position is lost or on stage
                            let curMonitor = monitors.first(where: { $0.frame.contains(orig.origin) }) ?? monitors.first(where: { $0.name == window.monitorName }) ?? monitor
                            if curMonitor.id != monitor.id {
                                let rx = orig.origin.x - curMonitor.frame.origin.x
                                let ry = orig.origin.y - curMonitor.frame.origin.y
                                targetFrame = NSRect(x: monitor.frame.origin.x + rx, y: monitor.frame.origin.y + ry, width: orig.width, height: orig.height)
                            } else { targetFrame = orig }
                        }
                        layouts.append(WindowLayout(windowNumber: winID, ownerPID: window.ownerPID, frame: targetFrame, isHidden: false, isFocused: window.isFocused, currentMonitorID: monitor.id))
                    } else {
                        layouts.append(WindowLayout(windowNumber: winID, ownerPID: window.ownerPID, frame: window.bounds, isHidden: true, isFocused: false, currentMonitorID: nil))
                    }
                }
            }
        }
        
        if targetFocusWinID == nil { targetFocusWinID = layouts.first(where: { !$0.isHidden })?.windowNumber }
        var screenResults: [ScreenWorkspaces] = []
        for monitor in sortedMonitors {
            let order = screenToWorkspaceOrder[monitor.id] ?? []
            screenResults.append(ScreenWorkspaces(screenID: monitor.id, screenName: monitor.name, workspaces: order.compactMap { workspaces[$0] }, activeWorkspaceID: activeWorkspacePerScreen[monitor.id]))
        }
        lastSwitchedScreenID = nil
        return ReconciliationResult(layouts: layouts, screenWorkspaces: screenResults, targetFocusWindowNumber: targetFocusWinID)
    }

    private func assignWorkspacesToNewWindows(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        let currentScreenIDs = Set(monitors.map { $0.id })
        let reconnectedIDs = disconnectedDisplayIDs.intersection(currentScreenIDs)
        disconnectedDisplayIDs.subtract(reconnectedIDs)
        for window in windows {
            let winID = window.windowNumber
            if let wsID = windowToWorkspace[winID] {
                if let lastID = windowToLastDisplayID[winID], lastID != workspaceToScreen[wsID], reconnectedIDs.contains(lastID) {
                    let oldScreen = workspaceToScreen[wsID]
                    workspaceToScreen[wsID] = lastID
                    activeWorkspacePerScreen[lastID] = wsID
                    if let oldS = oldScreen { screenToWorkspaceOrder[oldS]?.removeAll(where: { $0 == wsID }) }
                    if !(screenToWorkspaceOrder[lastID]?.contains(wsID) ?? false) { screenToWorkspaceOrder[lastID, default: []].append(wsID) }
                }
                if let assigned = workspaceToScreen[wsID], !currentScreenIDs.contains(assigned) {
                    disconnectedDisplayIDs.insert(assigned)
                    let fallback = monitors.first?.id ?? "unknown"
                    workspaceToScreen[wsID] = fallback
                    screenToWorkspaceOrder[assigned]?.removeAll(where: { $0 == wsID })
                    if !(screenToWorkspaceOrder[fallback]?.contains(wsID) ?? false) { screenToWorkspaceOrder[fallback, default: []].append(wsID) }
                }
            } else {
                // NEW WINDOW DISCOVERY:
                if abs(window.bounds.origin.x) < Configuration.visibleThreshold {
                    AppLog.debug("Discovery capture for window \(winID) (\(window.ownerName)): \(window.bounds)", logger: AppLog.windowState)
                    windowToLastRect[winID] = window.bounds
                    if let actual = monitors.first(where: { $0.frame.contains(window.bounds.origin) }) {
                        windowToLastDisplayID[winID] = actual.id
                    }
                }

                let screenID = pickBestScreenForWindow(window, monitors: monitors)
                let wsID = isManagedApp(bundleID: window.bundleID) ? createWorkspace(screenID: screenID, isManaged: true) : findOrCreateActiveUnmanagedWorkspace(screenID: screenID)
                addWindowToWorkspace(windowID: winID, workspaceID: wsID, pid: window.ownerPID)
            }
        }
        let currentIDs = Set(windows.map { $0.windowNumber })
        for (winID, wsID) in windowToWorkspace where !currentIDs.contains(winID) {
            windowToWorkspace.removeValue(forKey: winID)
            windowToPID.removeValue(forKey: winID)
            windowToLastDisplayID.removeValue(forKey: winID)
            windowToLastRect.removeValue(forKey: winID)
            workspaces[wsID]?.windowIDs.remove(winID)
        }
        for (wsID, ws) in workspaces where ws.windowIDs.isEmpty {
            workspaces.removeValue(forKey: wsID)
            if let sID = workspaceToScreen[wsID] { screenToWorkspaceOrder[sID]?.removeAll(where: { $0 == wsID }) }
            workspaceToScreen.removeValue(forKey: wsID)
            activeWorkspacePerScreen.filter { $0.value == wsID }.forEach { activeWorkspacePerScreen.removeValue(forKey: $0.key) }
        }
    }

    private func pickBestScreenForWindow(_ window: WindowStateStore.WindowSnapshot, monitors: [MonitorStateStore.MonitorSnapshot]) -> String {
        if let cur = monitors.first(where: { $0.name == window.monitorName }) { return cur.id }
        guard let bid = window.bundleID, monitors.count > 1 else { return monitors.first?.id ?? "unknown" }
        if isManagedApp(bundleID: bid) {
            var counts: [String: Int] = [:]
            for monitor in monitors {
                counts[monitor.id] = (screenToWorkspaceOrder[monitor.id] ?? []).compactMap { workspaces[$0] }.filter { $0.isManaged }.count
            }
            if let best = counts.min(by: { $0.value < $1.value })?.key { return best }
        }
        return monitors.first?.id ?? "unknown"
    }

    private func updateActiveWorkspaces(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        if let lastSwitch = lastManualSwitchTime, Date().timeIntervalSince(lastSwitch) < 0.25 { return }
        if let focused = windows.first(where: { $0.isFocused }), let wsID = windowToWorkspace[focused.windowNumber], let screenID = workspaceToScreen[wsID] {
            if abs(focused.bounds.origin.x) < Configuration.visibleThreshold { activeWorkspacePerScreen[screenID] = wsID }
        }
        for monitor in monitors {
            if activeWorkspacePerScreen[monitor.id] == nil {
                if let first = screenToWorkspaceOrder[monitor.id]?.first { activeWorkspacePerScreen[monitor.id] = first }
            }
        }
    }

    private func createWorkspace(screenID: String, isManaged: Bool) -> Int {
        let wsID = nextWorkspaceID
        nextWorkspaceID += 1
        workspaces[wsID] = Workspace(id: wsID, windowIDs: [], isManaged: isManaged)
        workspaceToScreen[wsID] = screenID
        var order = screenToWorkspaceOrder[screenID] ?? []
        order.append(wsID)
        screenToWorkspaceOrder[screenID] = order
        return wsID
    }

    private func addWindowToWorkspace(windowID: Int, workspaceID: Int, pid: pid_t) {
        windowToWorkspace[windowID] = workspaceID
        windowToPID[windowID] = pid
        workspaces[workspaceID]?.windowIDs.insert(windowID)
    }

    private func findOrCreateActiveUnmanagedWorkspace(screenID: String) -> Int {
        if let activeID = activeWorkspacePerScreen[screenID], let ws = workspaces[activeID], !ws.isManaged { return activeID }
        let order = screenToWorkspaceOrder[screenID] ?? []
        if let first = order.first(where: { workspaces[$0]?.isManaged == false }) { return first }
        return createWorkspace(screenID: screenID, isManaged: false)
    }

    func getStatusText(for screen: ScreenWorkspaces, windows: [WindowStateStore.WindowSnapshot]) -> String {
        if screen.workspaces.isEmpty { return "  (No windows)" }
        var lines: [String] = []
        for (index, ws) in screen.workspaces.enumerated() {
            let prefix = (ws.id == screen.activeWorkspaceID) ? "> " : "  "
            let unmanagedMarker = ws.isManaged ? "" : "G: "
            let winNames = ws.windowIDs.compactMap { id in windows.first(where: { $0.windowNumber == id })?.ownerName }
            let name: String
            if winNames.isEmpty { name = "Empty" }
            else if winNames.count <= 5 { name = Array(Set(winNames)).sorted().joined(separator: ", ") }
            else { 
                let unique = Array(Set(winNames)).sorted()
                name = "\(unique[0]) + \(winNames.count - 1) others"
            }
            lines.append("\(prefix)\(index + 1): \(unmanagedMarker)\(name)")
        }
        return lines.joined(separator: "\n")
    }
}
