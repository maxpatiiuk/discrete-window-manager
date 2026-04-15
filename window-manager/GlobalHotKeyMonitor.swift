//
// Captures a global hotkey and suppresses the matching key event to avoid double handling in other apps.

import AppKit
import CoreGraphics
import Foundation

final class GlobalHotKeyMonitor {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    private let handler: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(key: String, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.key = key.lowercased()
        self.modifiers = modifiers
        self.handler = handler
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard type == .keyDown,
                      let userInfo,
                      let nsevent = NSEvent(cgEvent: event) else {
                    return Unmanaged.passRetained(event)
                }

                let monitor = Unmanaged<GlobalHotKeyMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if monitor.matches(event: nsevent) {
                    AppLog.debug("Received global hotkey for \(monitor.shortcutDescription)", logger: AppLog.hotKey)
                    monitor.handler()
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: ref
        ) else {
            AppLog.error(
                "Failed to create global hotkey event tap. Check Input Monitoring/Accessibility permissions.",
                logger: AppLog.hotKey
            )
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source

        AppLog.debug("Registered global hotkey \(shortcutDescription)", logger: AppLog.hotKey)
    }

    func stop() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        AppLog.debug("Stopped global hotkey monitor", logger: AppLog.hotKey)
    }

    private func matches(event: NSEvent) -> Bool {
        guard !event.isARepeat else {
            return false
        }

        let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        return activeModifiers == modifiers
            && event.charactersIgnoringModifiers?.lowercased() == key
    }

    var shortcutDescription: String {
        var parts: [String] = []

        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Option")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if modifiers.contains(.command) {
            parts.append("Command")
        }

        parts.append(key.uppercased())
        return parts.joined(separator: "+")
    }
}
