//
// Wraps macOS Accessibility trust checks and prompt flow used by window-management features.

import AppKit
import Foundation

enum AccessibilityPermissionManager {
    static let shared = AccessibilityPermissionManager.self

    static func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}