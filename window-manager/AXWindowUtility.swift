import AppKit
import ApplicationServices

@MainActor
final class AXWindowUtility {
    static let shared = AXWindowUtility()
    
    // Off-screen coordinates for hiding windows
    static let stageOffset: CGFloat = 30000
    
    /// Finds the AXUIElement for a given CGWindowID and PID.
    func findWindowElement(windowID: Int, pid: pid_t) -> AXUIElement? {
        let start = DispatchTime.now()
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }
        
        for window in windows {
            var idValue: CGWindowID = 0
            _AXUIElementGetWindow(window, &idValue)
            if Int(idValue) == windowID {
                let end = DispatchTime.now()
                let nano = end.uptimeNanoseconds - start.uptimeNanoseconds
                if nano > 10_000_000 { // Log if slower than 10ms
                    AppLog.debug("findWindowElement \(windowID) took \(Double(nano)/1_000_000)ms", logger: AppLog.windowState)
                }
                return window
            }
        }
        
        return nil
    }

    func setWindowFrame(windowID: Int, pid: pid_t, frame: NSRect) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { 
            AppLog.error("Failed to find window \(windowID) for resizing", logger: AppLog.windowState)
            return 
        }
        
        let start = DispatchTime.now()
        
        var point = frame.origin
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        }
        
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }
        
        // Double check if size was applied
        var currentSize = CGSize.zero
        var currentSizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &currentSizeValue) == .success,
           let val = currentSizeValue as! AXValue?,
           AXValueGetValue(val, .cgSize, &currentSize) {
            
            if abs(currentSize.width - frame.size.width) > 2 || abs(currentSize.height - frame.size.height) > 2 {
                if let sizeValue = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
                }
            }
        }
        
        let end = DispatchTime.now()
        let ms = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        AppLog.debug("setWindowFrame \(windowID) to \(frame) took \(String(format: "%.2f", ms))ms", logger: AppLog.windowState)
    }

    func hideWindow(windowID: Int, pid: pid_t) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return }
        
        AppLog.debug("Hiding window \(windowID) by moving to stage", logger: AppLog.windowState)
        var point = CGPoint(x: Self.stageOffset, y: Self.stageOffset)
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        }
    }

    func warpMouse(to point: CGPoint) {
        AppLog.debug("Warping mouse to \(point)", logger: AppLog.indicator)
        CGWarpMouseCursorPosition(point)
    }

    func focusWindow(windowID: Int, pid: pid_t) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return }
        
        AppLog.debug("Focusing window \(windowID)", logger: AppLog.windowState)
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // 1. Set the window as the focused window of its application
        // This is often more reliable than setting kAXFocusedAttribute on the window itself
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        
        // 2. Set the window as the main window
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        
        // 3. Set the window as the focused window
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        
        // 4. Make sure the application is active
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
        }
        
        // 5. Raise the window to the front
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}

// Private header for the undocumented function
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
