//
// Maintains an up-to-date monitor snapshot and refreshes it when macOS display topology changes.

import AppKit
import Foundation

@MainActor
final class MonitorStateStore {
    struct MonitorSnapshot: Equatable {
        let id: String
        let name: String
        let frame: NSRect        // Top-left coordinates
        let visibleFrame: NSRect // Top-left coordinates
        let scale: CGFloat
        let isMain: Bool
    }

    private(set) var monitors: [MonitorSnapshot] = []
    var onMonitorsChanged: (() -> Void)?
    private var observer: NSObjectProtocol?

    func startWatching() {
        guard observer == nil else {
            return
        }

        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        AppLog.debug("Started monitor state watcher", logger: AppLog.monitorState)
    }

    func stopWatching() {
        guard let observer else {
            return
        }

        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
        AppLog.debug("Stopped monitor state watcher", logger: AppLog.monitorState)
    }

    func refresh() {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return }
        let primaryHeight = primaryScreen.frame.height

        let updated = screens.map { screen in
            // Convert from Cocoa (bottom-left) to Global (top-left) coordinates
            // In global coordinates, y=0 is the top of the primary screen.
            let frame = cocoaToGlobal(screen.frame, primaryHeight: primaryHeight)
            let visibleFrame = cocoaToGlobal(screen.visibleFrame, primaryHeight: primaryHeight)

            return MonitorSnapshot(
                id: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    .map { String(describing: $0) } ?? "unknown",
                name: screen.localizedName,
                frame: frame,
                visibleFrame: visibleFrame,
                scale: screen.backingScaleFactor,
                isMain: screen == primaryScreen
            )
        }

        if updated != monitors {
            monitors = updated
            AppLog.info("Monitor topology updated (\(updated.count) display(s))", logger: AppLog.monitorState)
            onMonitorsChanged?()
        }
    }

    private func cocoaToGlobal(_ rect: NSRect, primaryHeight: CGFloat) -> NSRect {
        // Cocoa: y=0 at bottom. Global: y=0 at top.
        return NSRect(
            x: rect.origin.x,
            y: primaryHeight - (rect.origin.y + rect.size.height),
            width: rect.size.width,
            height: rect.size.height
        )
    }

    func debugText() -> String {
        guard !monitors.isEmpty else {
            return "Monitors\n- No screens detected"
        }

        var lines = ["Monitors (\(monitors.count))"]

        for (index, monitor) in monitors.enumerated() {
            lines.append("- #\(index + 1): \(monitor.name)\(monitor.isMain ? " main" : "")")
            lines.append("  id:      \(monitor.id)")
            lines.append("  frame:   \(rectDescription(monitor.frame))")
            lines.append("  visible: \(rectDescription(monitor.visibleFrame))")
            lines.append("  scale:   \(String(format: "%.2f", monitor.scale))")
        }

        return lines.joined(separator: "\n")
    }

    private func rectDescription(_ rect: NSRect) -> String {
        "x=\(Int(rect.origin.x)), y=\(Int(rect.origin.y)), w=\(Int(rect.size.width)), h=\(Int(rect.size.height))"
    }
}
