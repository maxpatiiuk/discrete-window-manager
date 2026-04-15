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

    private let managedAppBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.google.chrome.for.testing",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    // Persistent state
    private var workspaces: [Int: Workspace] = [:]
    private var windowToWorkspace: [Int: Int] = [:] // windowID -> workspaceID
    private var workspaceToScreen: [Int: String] = [:] // workspaceID -> screenID
    private var activeWorkspacePerScreen: [String: Int] = [:] // screenID -> workspaceID
    private var windowToLastDisplayID: [Int: String] = [:] // windowID -> last physical screen ID
    private var disconnectedDisplayIDs: Set<String> = []
    
    private var nextWorkspaceID = 1
    private var lastManualSwitchTime: Date?
    private var lastSwitchedScreenID: String?

    func toggleManaged(workspaceID: Int) {
        if var ws = workspaces[workspaceID] {
            ws.isManaged.toggle()
            workspaces[workspaceID] = ws
            AppLog.info("Workspace \(workspaceID) managed status: \(ws.isManaged)", logger: AppLog.app)
        }
    }

    func isWorkspaceManaged(id: Int) -> Bool {
        return workspaces[id]?.isManaged ?? false
    }

    func switchToWorkspace(screenIndex: Int, workspaceIndex: Int, monitors: [MonitorStateStore.MonitorSnapshot]) {
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { 
            AppLog.debug("switchToWorkspace: screenIndex \(screenIndex) out of bounds (\(sortedMonitors.count) monitors)", logger: AppLog.hotKey)
            return 
        }
        let monitor = sortedMonitors[screenIndex]
        
        let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }.sorted()
        guard !wsIDsOnScreen.isEmpty else { 
            AppLog.debug("switchToWorkspace: no workspaces on screen \(monitor.name)", logger: AppLog.hotKey)
            return 
        }

        if workspaceIndex >= wsIDsOnScreen.count {
            AppLog.debug("switchToWorkspace: index \(workspaceIndex) exceeds workspace count (\(wsIDsOnScreen.count)) on screen \(monitor.name), clamping to last", logger: AppLog.hotKey)
        }
        
        let targetIndex = min(workspaceIndex, wsIDsOnScreen.count - 1)
        let targetWSID = wsIDsOnScreen[targetIndex]
        
        AppLog.info("Switching Screen #\(screenIndex + 1) (\(monitor.name)) to Workspace index \(targetIndex) (ID \(targetWSID))", logger: AppLog.app)
        activeWorkspacePerScreen[monitor.id] = targetWSID
        lastManualSwitchTime = Date()
        lastSwitchedScreenID = monitor.id
    }

    func cycleWorkspace(screenIndex: Int, monitors: [MonitorStateStore.MonitorSnapshot]) {
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { return }
        let monitor = sortedMonitors[screenIndex]
        
        let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }.sorted()
        guard !wsIDsOnScreen.isEmpty else { return }
        
        let currentWSID = activeWorkspacePerScreen[monitor.id] ?? wsIDsOnScreen[0]
        if let currentIndex = wsIDsOnScreen.firstIndex(of: currentWSID) {
            let nextIndex = (currentIndex + 1) % wsIDsOnScreen.count
            let targetWSID = wsIDsOnScreen[nextIndex]
            AppLog.info("Cycling Screen #\(screenIndex + 1) (\(monitor.name)) to Workspace \(targetWSID)", logger: AppLog.app)
            activeWorkspacePerScreen[monitor.id] = targetWSID
            lastManualSwitchTime = Date()
            lastSwitchedScreenID = monitor.id
        }
    }

    func moveFocusedWindowToScreen(screenIndex: Int, windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        guard let focused = windows.first(where: { $0.isFocused }) else { return }
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
        guard screenIndex < sortedMonitors.count else { return }
        let targetMonitor = sortedMonitors[screenIndex]
        
        let winID = focused.windowNumber
        guard let oldWSID = windowToWorkspace[winID] else { return }
        let sourceScreenID = workspaceToScreen[oldWSID]
        
        if sourceScreenID == targetMonitor.id {
            let newWSID = createWorkspace(screenID: targetMonitor.id, isManaged: workspaces[oldWSID]?.isManaged ?? false)
            AppLog.info("Splitting window \(winID) to NEW Workspace \(newWSID) on screen \(targetMonitor.name)", logger: AppLog.app)
            moveWindowToWorkspace(windowID: winID, from: oldWSID, to: newWSID)
            activeWorkspacePerScreen[targetMonitor.id] = newWSID
            windowToLastDisplayID[winID] = targetMonitor.id
            lastManualSwitchTime = Date()
            lastSwitchedScreenID = targetMonitor.id
            return
        }

        // Move the window to a fresh workspace on the target screen
        let isManaged = workspaces[oldWSID]?.isManaged ?? true
        let newWSID = createWorkspace(screenID: targetMonitor.id, isManaged: isManaged)
        AppLog.info("Moving window \(winID) to Screen #\(screenIndex + 1) (\(targetMonitor.name)) (New WS \(newWSID))", logger: AppLog.app)
        moveWindowToWorkspace(windowID: winID, from: oldWSID, to: newWSID)
        activeWorkspacePerScreen[targetMonitor.id] = newWSID
        windowToLastDisplayID[winID] = targetMonitor.id
        
        // --- IMPROVEMENT: Don't leave the source screen blank ---
        if let sourceID = sourceScreenID {
            let remainingWSIDs = workspaceToScreen.filter { $0.value == sourceID && $0.key != oldWSID }.map { $0.key }.sorted()
            if let firstRemaining = remainingWSIDs.first {
                AppLog.debug("Source screen \(sourceID) switched to Workspace \(firstRemaining) to avoid being blank", logger: AppLog.app)
                activeWorkspacePerScreen[sourceID] = firstRemaining
            }
        }
        
        lastManualSwitchTime = Date()
        lastSwitchedScreenID = targetMonitor.id // Ensure focus ends up on the new screen
    }

    private func moveWindowToWorkspace(windowID: Int, from oldWSID: Int, to newWSID: Int) {
        workspaces[oldWSID]?.windowIDs.remove(windowID)
        windowToWorkspace[windowID] = newWSID
        workspaces[newWSID]?.windowIDs.insert(windowID)
    }

    func reconcile(windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) -> ReconciliationResult {
        assignWorkspacesToNewWindows(windows, monitors: monitors)
        updateActiveWorkspaces(windows, monitors: monitors)

        var layouts: [WindowLayout] = []
        var targetFocusWinID: Int?
        
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }

        #if DEBUG
        for (i, m) in sortedMonitors.enumerated() {
            AppLog.debug("Monitor #\(i+1): \(m.name) id=\(m.id) x=\(Int(m.frame.origin.x))", logger: AppLog.monitorState)
        }
        #endif

        if let switchedID = lastSwitchedScreenID,
           let activeWSID = activeWorkspacePerScreen[switchedID],
           let ws = workspaces[activeWSID] {
            targetFocusWinID = ws.windowIDs.first(where: { winID in windows.contains(where: { $0.windowNumber == winID }) })
            if let tid = targetFocusWinID {
                AppLog.debug("Reconcile: Target focus set to window \(tid) on switched screen \(switchedID)", logger: AppLog.windowState)
            }
        }

        for monitor in sortedMonitors {
            let activeWSID = activeWorkspacePerScreen[monitor.id]
            let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }
            
            for wsID in wsIDsOnScreen {
                guard let ws = workspaces[wsID] else { continue }
                let isWSActive = (wsID == activeWSID)
                
                for winID in ws.windowIDs {
                    guard let window = windows.first(where: { $0.windowNumber == winID }) else { continue }
                    if isWSActive {
                        if targetFocusWinID == nil && window.isFocused {
                            targetFocusWinID = winID
                        }

                        let targetFrame: NSRect
                        if ws.isManaged {
                            targetFrame = monitor.frame
                        } else {
                            let currentMonitor = monitors.first(where: { $0.frame.contains(window.bounds.origin) })
                                ?? monitors.first(where: { $0.name == window.monitorName })
                                ?? monitor
                            
                            if currentMonitor.id != monitor.id {
                                let relativeX = window.bounds.origin.x - currentMonitor.frame.origin.x
                                let relativeY = window.bounds.origin.y - currentMonitor.frame.origin.y
                                targetFrame = NSRect(
                                    x: monitor.frame.origin.x + relativeX,
                                    y: monitor.frame.origin.y + relativeY,
                                    width: window.bounds.width,
                                    height: window.bounds.height
                                )
                            } else {
                                targetFrame = window.bounds
                            }
                        }
                        layouts.append(WindowLayout(
                            windowNumber: winID,
                            ownerPID: window.ownerPID,
                            frame: targetFrame,
                            isHidden: false,
                            isFocused: window.isFocused,
                            currentMonitorID: monitors.first(where: { $0.name == window.monitorName })?.id
                        ))
                    } else {
                        layouts.append(WindowLayout(
                            windowNumber: winID,
                            ownerPID: window.ownerPID,
                            frame: window.bounds,
                            isHidden: true,
                            isFocused: false,
                            currentMonitorID: monitors.first(where: { $0.name == window.monitorName })?.id
                        ))
                    }
                }
            }
        }
        
        if targetFocusWinID == nil {
            targetFocusWinID = layouts.first(where: { !$0.isHidden })?.windowNumber
        }

        var screenResults: [ScreenWorkspaces] = []
        for monitor in sortedMonitors {
            let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }.sorted()
            let monitorWorkspaces = wsIDsOnScreen.compactMap { workspaces[$0] }
            
            screenResults.append(ScreenWorkspaces(
                screenID: monitor.id,
                screenName: monitor.name,
                workspaces: monitorWorkspaces,
                activeWorkspaceID: activeWorkspacePerScreen[monitor.id]
            ))
        }

        lastSwitchedScreenID = nil // Reset after reconciliation
        return ReconciliationResult(layouts: layouts, screenWorkspaces: screenResults, targetFocusWindowNumber: targetFocusWinID)
    }

    private func assignWorkspacesToNewWindows(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        let currentScreenIDs = Set(monitors.map { $0.id })
        
        let reconnectedIDs = disconnectedDisplayIDs.intersection(currentScreenIDs)
        disconnectedDisplayIDs.subtract(reconnectedIDs)

        for window in windows {
            let winID = window.windowNumber

            if let wsID = windowToWorkspace[winID] {
                // Window already has a workspace. Check for display reconnection.
                if let lastID = windowToLastDisplayID[winID],
                   lastID != workspaceToScreen[wsID],
                   reconnectedIDs.contains(lastID) {
                    
                    AppLog.info("Home display \(lastID) reconnected. Moving window \(winID) back.", logger: AppLog.app)
                    workspaceToScreen[wsID] = lastID
                    activeWorkspacePerScreen[lastID] = wsID
                }
                
                // Handle display disconnection
                if let assignedScreen = workspaceToScreen[wsID], !currentScreenIDs.contains(assignedScreen) {
                    disconnectedDisplayIDs.insert(assignedScreen)
                    let fallbackScreen = monitors.first?.id ?? "unknown"
                    AppLog.info("Display \(assignedScreen) disconnected. Moving Workspace \(wsID) to \(fallbackScreen)", logger: AppLog.app)
                    workspaceToScreen[wsID] = fallbackScreen
                }
            } else {
                // New window discovery
                let screenID = pickBestScreenForWindow(window, monitors: monitors)
                
                if let bundleID = window.bundleID, managedAppBundleIDs.contains(bundleID) {
                    let wsID = createWorkspace(screenID: screenID, isManaged: true)
                    AppLog.info("New managed window \(winID) (\(window.ownerName)) -> New Workspace \(wsID)", logger: AppLog.app)
                    addWindowToWorkspace(windowID: winID, workspaceID: wsID)
                } else {
                    let wsID = findOrCreateActiveUnmanagedWorkspace(screenID: screenID)
                    AppLog.info("New unmanaged window \(winID) (\(window.ownerName)) -> Existing Workspace \(wsID)", logger: AppLog.app)
                    addWindowToWorkspace(windowID: winID, workspaceID: wsID)
                }
            }
            
            // Update last known physical display if window is currently visible
            if window.bounds.origin.x < AXWindowUtility.stageOffset {
                if let actualMonitor = monitors.first(where: { $0.frame.contains(window.bounds.origin) }) {
                    windowToLastDisplayID[winID] = actualMonitor.id
                }
            }
        }
        
        // Cleanup
        let currentWindowIDs = Set(windows.map { $0.windowNumber })
        for (winID, wsID) in windowToWorkspace where !currentWindowIDs.contains(winID) {
            AppLog.debug("Removing window \(winID) from Workspace \(wsID)", logger: AppLog.windowState)
            windowToWorkspace.removeValue(forKey: winID)
            windowToLastDisplayID.removeValue(forKey: winID)
            workspaces[wsID]?.windowIDs.remove(winID)
        }
        
        for (wsID, ws) in workspaces where ws.windowIDs.isEmpty {
            AppLog.debug("Removing empty Workspace \(wsID)", logger: AppLog.windowState)
            workspaces.removeValue(forKey: wsID)
            workspaceToScreen.removeValue(forKey: wsID)
            for (sID, aWSID) in activeWorkspacePerScreen where aWSID == wsID {
                activeWorkspacePerScreen.removeValue(forKey: sID)
            }
        }
    }

    private func pickBestScreenForWindow(_ window: WindowStateStore.WindowSnapshot, monitors: [MonitorStateStore.MonitorSnapshot]) -> String {
        if let currentScreen = monitors.first(where: { $0.name == window.monitorName }) {
            return currentScreen.id
        }

        guard let bundleID = window.bundleID, monitors.count > 1 else {
            return monitors.first?.id ?? "unknown"
        }

        let isChrome = bundleID.contains("com.google.Chrome") && !window.title.contains("DevTools")
        let isVSCode = bundleID == "com.microsoft.VSCode"
        let isDevTools = window.title.contains("DevTools")

        if isChrome || isVSCode || isDevTools {
            var screenConflicts: [String: Int] = [:]
            for monitor in monitors {
                let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }
                var count = 0
                for wsID in wsIDsOnScreen {
                    if let ws = workspaces[wsID], ws.isManaged { count += 1 }
                }
                screenConflicts[monitor.id] = count
            }

            if let bestScreen = screenConflicts.min(by: { $0.value < $1.value })?.key {
                return bestScreen
            }
        }

        return monitors.first?.id ?? "unknown"
    }

    private func updateActiveWorkspaces(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        if let lastSwitch = lastManualSwitchTime, Date().timeIntervalSince(lastSwitch) < 0.25 {
            return
        }

        if let focused = windows.first(where: { $0.isFocused }),
           let wsID = windowToWorkspace[focused.windowNumber],
           let screenID = workspaceToScreen[wsID] {
            
            let isHidden = focused.bounds.origin.x >= AXWindowUtility.stageOffset
            
            if !isHidden {
                if activeWorkspacePerScreen[screenID] != wsID {
                    AppLog.debug("Screen \(screenID) active workspace changed to \(wsID) due to focus", logger: AppLog.windowState)
                    activeWorkspacePerScreen[screenID] = wsID
                }
            }
        }
        
        for monitor in monitors {
            if activeWorkspacePerScreen[monitor.id] == nil {
                let wsIDs = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }
                if let first = wsIDs.sorted().first {
                    activeWorkspacePerScreen[monitor.id] = first
                }
            }
        }
    }

    private func createWorkspace(screenID: String, isManaged: Bool) -> Int {
        let wsID = nextWorkspaceID
        nextWorkspaceID += 1
        workspaces[wsID] = Workspace(id: wsID, windowIDs: [], isManaged: isManaged)
        workspaceToScreen[wsID] = screenID
        return wsID
    }

    private func addWindowToWorkspace(windowID: Int, workspaceID: Int) {
        windowToWorkspace[windowID] = workspaceID
        workspaces[workspaceID]?.windowIDs.insert(windowID)
    }

    private func findOrCreateActiveUnmanagedWorkspace(screenID: String) -> Int {
        if let activeID = activeWorkspacePerScreen[screenID],
           let ws = workspaces[activeID], !ws.isManaged {
            return activeID
        }
        
        let unmanagedOnScreen = workspaceToScreen.filter { $0.value == screenID }
            .map { $0.key }
            .filter { workspaces[$0]?.isManaged == false }
        
        if let first = unmanagedOnScreen.sorted().first {
            return first
        }
        
        return createWorkspace(screenID: screenID, isManaged: false)
    }

    func getStatusText(for screen: ScreenWorkspaces, windows: [WindowStateStore.WindowSnapshot]) -> String {
        var lines = ["Workspaces: \(screen.screenName)"]
        if screen.workspaces.isEmpty {
            lines.append("  (No windows)")
            return lines.joined(separator: "\n")
        }

        for (index, ws) in screen.workspaces.enumerated() {
            let isWSActive = (ws.id == screen.activeWorkspaceID)
            let prefix = isWSActive ? "> " : "  "
            let managedMarker = ws.isManaged ? "[M] " : ""
            
            let winNames = ws.windowIDs.compactMap { id in
                windows.first(where: { $0.windowNumber == id })?.ownerName
            }
            
            let displayName: String
            if winNames.isEmpty {
                displayName = "Empty"
            } else if winNames.count == 1 {
                displayName = winNames[0]
            } else {
                displayName = "\(winNames[0]) + \(winNames.count - 1) others"
            }
            
            lines.append("\(prefix)\(index + 1): \(managedMarker)\(displayName)")
        }
        return lines.joined(separator: "\n")
    }
}
