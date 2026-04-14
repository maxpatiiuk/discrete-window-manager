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
        let frame: NSRect
        let isHidden: Bool
    }

    struct ReconciliationResult {
        let layouts: [WindowLayout]
        let screenWorkspaces: [ScreenWorkspaces]
    }

    struct ScreenWorkspaces {
        let screenID: String
        let screenName: String
        let workspaces: [Workspace]
        let activeWorkspaceID: Int?
    }

    private let managedAppBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    // Persistent state
    private var workspaces: [Int: Workspace] = [:]
    private var windowToWorkspace: [Int: Int] = [:] // windowID -> workspaceID
    private var workspaceToScreen: [Int: String] = [:] // workspaceID -> screenID
    private var activeWorkspacePerScreen: [String: Int] = [:] // screenID -> workspaceID
    
    private var nextWorkspaceID = 1

    func toggleManaged(workspaceID: Int) {
        if var ws = workspaces[workspaceID] {
            ws.isManaged.toggle()
            workspaces[workspaceID] = ws
        }
    }

    func reconcile(windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) -> ReconciliationResult {
        // 1. Assign new windows to workspaces
        assignWorkspacesToNewWindows(windows, monitors: monitors)

        // 2. Determine active workspace per screen based on focus
        updateActiveWorkspaces(windows, monitors: monitors)

        // 3. Generate layouts
        var layouts: [WindowLayout] = []
        for monitor in monitors {
            let activeWSID = activeWorkspacePerScreen[monitor.id]
            
            // Find all workspaces assigned to this screen
            let wsIDsOnScreen = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }
            
            for wsID in wsIDsOnScreen {
                guard let ws = workspaces[wsID] else { continue }
                let isWSActive = (wsID == activeWSID)
                
                for winID in ws.windowIDs {
                    guard let window = windows.first(where: { $0.windowNumber == winID }) else { continue }
                    
                    if isWSActive {
                        // Window should be visible
                        let targetFrame: NSRect
                        if ws.isManaged {
                            targetFrame = monitor.visibleFrame
                        } else {
                            targetFrame = window.bounds // Keep original bounds for unmanaged
                        }
                        layouts.append(WindowLayout(windowNumber: winID, frame: targetFrame, isHidden: false))
                    } else {
                        // Window should be hidden on "The Stage"
                        layouts.append(WindowLayout(windowNumber: winID, frame: window.bounds, isHidden: true))
                    }
                }
            }
        }

        // 4. Build status result
        var screenResults: [ScreenWorkspaces] = []
        let sortedMonitors = monitors.sorted { $0.frame.origin.x < $1.frame.origin.x }
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

        return ReconciliationResult(layouts: layouts, screenWorkspaces: screenResults)
    }

    private func assignWorkspacesToNewWindows(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        for window in windows {
            if windowToWorkspace[window.windowNumber] == nil {
                let screenID = monitors.first(where: { $0.name == window.monitorName })?.id ?? monitors.first?.id ?? "unknown"
                
                if let bundleID = window.bundleID, managedAppBundleIDs.contains(bundleID) {
                    // New managed app gets its own managed workspace
                    let wsID = createWorkspace(screenID: screenID, isManaged: true)
                    addWindowToWorkspace(windowID: window.windowNumber, workspaceID: wsID)
                } else {
                    // Unmanaged app goes to the current active unmanaged workspace on this screen,
                    // or a new one if none exists.
                    let wsID = findOrCreateActiveUnmanagedWorkspace(screenID: screenID)
                    addWindowToWorkspace(windowID: window.windowNumber, workspaceID: wsID)
                }
            }
        }
        
        // Cleanup windows that no longer exist
        let currentWindowIDs = Set(windows.map { $0.windowNumber })
        for (winID, wsID) in windowToWorkspace where !currentWindowIDs.contains(winID) {
            windowToWorkspace.removeValue(forKey: winID)
            workspaces[wsID]?.windowIDs.remove(winID)
        }
        
        // Cleanup empty workspaces (except maybe the last unmanaged one)
        for (wsID, ws) in workspaces where ws.windowIDs.isEmpty {
            // We can keep it or remove it. Let's remove for now.
            workspaces.removeValue(forKey: wsID)
            workspaceToScreen.removeValue(forKey: wsID)
            if activeWorkspacePerScreen.values.contains(wsID) {
                // Remove from active map if it was there
                for (sID, aWSID) in activeWorkspacePerScreen where aWSID == wsID {
                    activeWorkspacePerScreen.removeValue(forKey: sID)
                }
            }
        }
    }

    private func updateActiveWorkspaces(_ windows: [WindowStateStore.WindowSnapshot], monitors: [MonitorStateStore.MonitorSnapshot]) {
        if let focused = windows.first(where: { $0.isFocused }),
           let wsID = windowToWorkspace[focused.windowNumber],
           let screenID = workspaceToScreen[wsID] {
            activeWorkspacePerScreen[screenID] = wsID
        }
        
        // Ensure every screen has an active workspace if it has any
        for monitor in monitors {
            if activeWorkspacePerScreen[monitor.id] == nil {
                let wsIDs = workspaceToScreen.filter { $0.value == monitor.id }.map { $0.key }
                if let first = wsIDs.first {
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
        
        // Try to find any unmanaged workspace on this screen
        let unmanagedOnScreen = workspaceToScreen.filter { $0.value == screenID }
            .map { $0.key }
            .filter { workspaces[$0]?.isManaged == false }
        
        if let first = unmanagedOnScreen.first {
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
