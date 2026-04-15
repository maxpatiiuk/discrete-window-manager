import AppKit
import Foundation

@MainActor
final class Actuator {
    private var lastKnownLayouts: [Int: WorkspaceManager.WindowLayout] = [:]
    
    func apply(layouts: [WorkspaceManager.WindowLayout]) {
        for layout in layouts {
            let winID = layout.windowNumber
            let prev = lastKnownLayouts[winID]
            
            // Only actuate if state changed
            if prev == nil || prev!.isHidden != layout.isHidden || prev!.frame != layout.frame {
                if layout.isHidden {
                    AppLog.debug("Actuator: Hiding win \(winID)", logger: AppLog.windowState)
                    AXWindowUtility.shared.hideWindow(windowID: winID, pid: layout.ownerPID)
                } else {
                    AppLog.debug("Actuator: Showing/Moving win \(winID) to \(layout.frame)", logger: AppLog.windowState)
                    AXWindowUtility.shared.setWindowFrame(windowID: winID, pid: layout.ownerPID, frame: layout.frame)
                }
            }
            
            lastKnownLayouts[winID] = layout
        }
        
        // Clean up windows that are no longer in our layout
        let currentIDs = Set(layouts.map { $0.windowNumber })
        let disappeared = lastKnownLayouts.keys.filter { !currentIDs.contains($0) }
        for id in disappeared {
            lastKnownLayouts.removeValue(forKey: id)
        }
    }
}
