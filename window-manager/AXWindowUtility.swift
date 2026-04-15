import AppKit
import ApplicationServices

@MainActor
final class AXWindowUtility {
    static let shared = AXWindowUtility()
    static let stageOffset = Configuration.stageOffset
    
    func findWindowElement(windowID: Int, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else { return nil }
        for window in windows {
            var idValue: CGWindowID = 0
            _ = _AXUIElementGetWindow(window, &idValue)
            if Int(idValue) == windowID { return window }
        }
        return nil
    }

    func getWindowFrame(windowID: Int, pid: pid_t) -> NSRect? {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        var posValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           let val = posValue as! AXValue? {
            AXValueGetValue(val, .cgPoint, &position)
        } else { return nil }
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let val = sizeValue as! AXValue? {
            AXValueGetValue(val, .cgSize, &size)
        } else { return nil }
        return NSRect(origin: position, size: size)
    }

    func setWindowFrame(windowID: Int, pid: pid_t, frame: NSRect) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return }
        var point = frame.origin
        var size = frame.size
        if let v = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) }
    }

    func hideWindow(windowID: Int, pid: pid_t) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return }
        var point = CGPoint(x: Self.stageOffset, y: Self.stageOffset)
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        }
    }

    func warpMouse(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    func focusWindow(windowID: Int, pid: pid_t) {
        guard let element = findWindowElement(windowID: windowID, pid: pid) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}
