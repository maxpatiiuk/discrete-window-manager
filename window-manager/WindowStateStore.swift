//
// Maintains live window snapshots (monitor/space/focus) using AX and workspace event triggers.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class WindowStateStore {
    struct WindowSnapshot: Equatable {
        let windowNumber: Int
        let ownerName: String
        let ownerPID: Int32
        let bundleID: String?
        let title: String
        let bounds: NSRect
        let monitorName: String?
        let spaceID: Int?
        let isFocused: Bool
    }

    private struct FocusedWindowDescriptor {
        let title: String?
        let frame: NSRect?
    }

    private struct DirtyFlags: OptionSet {
        let rawValue: Int

        static let full = DirtyFlags(rawValue: 1 << 0)
        static let focus = DirtyFlags(rawValue: 1 << 1)
        static let appWindows = DirtyFlags(rawValue: 1 << 2)
    }

    private(set) var windows: [WindowSnapshot] = []
    var onWindowsChanged: (() -> Void)?

    // The new Orchestrator
    private let axManager = AXObserverManager()
    
    // Debounce and dirty-state scheduler
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var dirtyFlags: DirtyFlags = []
    private var dirtyPIDs: Set<pid_t> = []
    private var refreshSequence = 0

    func startWatching() {
        // 1. Initial State Load
        fullRefresh()

        // 2. Setup the AX Observer Mesh (Sub-10ms triggers)
        axManager.handleWindowCreated = { [weak self] _, pid in
            Task { @MainActor [weak self] in
                self?.requestRefresh(flags: [.appWindows], pids: [pid])
            }
        }
        axManager.handleWindowFocused = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.requestRefresh(flags: [.focus])
            }
        }
        axManager.handleWindowDestroyed = { [weak self] _, pid in
            Task { @MainActor [weak self] in
                self?.requestRefresh(flags: [.appWindows], pids: [pid])
            }
        }
        axManager.startWatching()

        // 3. Setup Global Workspace Triggers (Space changes & App lifecycle)
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestRefresh(flags: [.focus])
                }
            }
        )

        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                Task { @MainActor [weak self] in
                    if let pid {
                        self?.requestRefresh(flags: [.appWindows, .focus], pids: [pid])
                    } else {
                        self?.requestRefresh(flags: [.full])
                    }
                }
            }
        )

        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestRefresh(flags: [.full])
                }
            }
        )

        AppLog.debug("Started event-driven window state watcher", logger: AppLog.windowState)
    }

    func stopWatching() {
        refreshTask?.cancel()
        refreshTask = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
        }
        observers.removeAll()

        axManager.stopWatching()

        AppLog.debug("Stopped window state watcher", logger: AppLog.windowState)
    }

    /// Debounces rapid event bursts and executes the cheapest valid reconciliation.
    private func requestRefresh(flags: DirtyFlags, pids: Set<pid_t> = []) {
        dirtyFlags.formUnion(flags)
        dirtyPIDs.formUnion(pids)

        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            // 20,000,000 nanoseconds = 20ms
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled else { return }
            self.processPendingRefresh()
        }
    }

    // MARK: - Refresh Pipeline

    func refresh() {
        requestRefresh(flags: [.full])
    }

    private func processPendingRefresh() {
        refreshSequence += 1
        let sequence = refreshSequence

        let pendingFlags = dirtyFlags
        let pendingPIDs = dirtyPIDs
        dirtyFlags = []
        dirtyPIDs.removeAll()

        AppLog.debug(
            "Refresh #\(sequence) start flags=\(describe(pendingFlags)) pids=\(describePids(pendingPIDs))",
            logger: AppLog.windowState
        )

        if pendingFlags.contains(.full) {
            let started = beginTimedRefresh(label: "full", sequence: sequence)
            fullRefresh()
            endTimedRefresh(label: "full", sequence: sequence, started: started)
            return
        }

        if pendingFlags.contains(.appWindows), !pendingPIDs.isEmpty {
            let started = beginTimedRefresh(label: "dirty-app", sequence: sequence)
            refreshDirtyApps(pids: pendingPIDs)
            endTimedRefresh(label: "dirty-app", sequence: sequence, started: started)
        }

        if pendingFlags.contains(.focus) {
            let started = beginTimedRefresh(label: "focus-only", sequence: sequence)
            applyFocusUpdateOnly()
            endTimedRefresh(label: "focus-only", sequence: sequence, started: started)
        }

        AppLog.debug("Refresh #\(sequence) complete", logger: AppLog.windowState)
    }

    private func fullRefresh() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)
        guard let raw = copyVisibleWindowInfo() else {
            return
        }

        let updated = buildSnapshots(
            from: raw,
            limitingPIDs: nil,
            frontmostPID: frontmostPID,
            focusedDescriptor: focusedDescriptor,
            existingWindows: []
        )

        applyWindowsIfChanged(updated)
    }

    private func refreshDirtyApps(pids: Set<pid_t>) {
        guard !pids.isEmpty,
              let raw = copyVisibleWindowInfo() else {
            return
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)

        let updated = buildSnapshots(
            from: raw,
            limitingPIDs: pids,
            frontmostPID: frontmostPID,
            focusedDescriptor: focusedDescriptor,
            existingWindows: windows
        )

        applyWindowsIfChanged(updated)
    }

    private func applyFocusUpdateOnly() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)
        let updated = applyingFocusMarkers(
            to: windows,
            frontmostPID: frontmostPID,
            focusedDescriptor: focusedDescriptor
        )

        applyWindowsIfChanged(updated)
    }

    private func copyVisibleWindowInfo() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
    }

    private func buildSnapshots(
        from raw: [[String: Any]],
        limitingPIDs: Set<pid_t>?,
        frontmostPID: pid_t?,
        focusedDescriptor: FocusedWindowDescriptor?,
        existingWindows: [WindowSnapshot]
    ) -> [WindowSnapshot] {
        var prefix: [WindowSnapshot] = []
        if let limitingPIDs {
            prefix = existingWindows.filter { !limitingPIDs.contains($0.ownerPID) }
        }

        var extracted: [WindowSnapshot] = []
        var bundleIDByPID: [pid_t: String] = [:]

        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let ownerPIDRaw = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            let ownerPID = Int32(ownerPIDRaw)
            if let limitingPIDs, !limitingPIDs.contains(ownerPID) {
                continue
            }

            if cgBounds.width < 24 || cgBounds.height < 24 {
                continue
            }

            let bundleID: String?
            if let cached = bundleIDByPID[ownerPID] {
                bundleID = cached
            } else {
                bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
                if let bundleID {
                    bundleIDByPID[ownerPID] = bundleID
                }
            }

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<untitled>"
            let monitorName = monitorName(for: cgBounds)
            let spaceID = (info["kCGWindowWorkspace"] as? NSNumber)?.intValue

            extracted.append(
                WindowSnapshot(
                    windowNumber: number,
                    ownerName: ownerName,
                    ownerPID: ownerPID,
                    bundleID: bundleID,
                    title: title,
                    bounds: cgBounds,
                    monitorName: monitorName,
                    spaceID: spaceID,
                    isFocused: false
                )
            )
        }

        let merged = prefix + extracted
        let withFocus = applyingFocusMarkers(
            to: merged,
            frontmostPID: frontmostPID,
            focusedDescriptor: focusedDescriptor
        )

        return sortByCurrentZOrder(withFocus, raw: raw)
    }

    private func sortByCurrentZOrder(_ snapshots: [WindowSnapshot], raw: [[String: Any]]) -> [WindowSnapshot] {
        var zIndexByWindowID: [Int: Int] = [:]
        zIndexByWindowID.reserveCapacity(raw.count)
        for (index, info) in raw.enumerated() {
            if let number = info[kCGWindowNumber as String] as? Int {
                zIndexByWindowID[number] = index
            }
        }

        return snapshots.sorted { lhs, rhs in
            let lhsZ = zIndexByWindowID[lhs.windowNumber] ?? Int.max
            let rhsZ = zIndexByWindowID[rhs.windowNumber] ?? Int.max
            if lhsZ != rhsZ {
                return lhsZ < rhsZ
            }
            return lhs.windowNumber < rhs.windowNumber
        }
    }

    private func applyingFocusMarkers(
        to snapshots: [WindowSnapshot],
        frontmostPID: pid_t?,
        focusedDescriptor: FocusedWindowDescriptor?
    ) -> [WindowSnapshot] {
        guard !snapshots.isEmpty else {
            return snapshots
        }

        var mutable = snapshots
        var focusedFound = false

        for index in mutable.indices {
            let snapshot = mutable[index]
            let shouldFocus = !focusedFound
                && snapshot.ownerPID == frontmostPID
                && matchesFocusedWindow(
                    title: snapshot.title,
                    bounds: snapshot.bounds,
                    focused: focusedDescriptor
                )

            if shouldFocus {
                mutable[index] = snapshot.withFocused(true)
                focusedFound = true
            } else if snapshot.isFocused {
                mutable[index] = snapshot.withFocused(false)
            }
        }

        if !focusedFound, let frontmostPID,
           let index = mutable.firstIndex(where: { $0.ownerPID == frontmostPID }) {
            mutable[index] = mutable[index].withFocused(true)
        }

        return mutable
    }

    private func applyWindowsIfChanged(_ updated: [WindowSnapshot]) {
        if updated != windows {
            windows = updated
            AppLog.debug("Window topology updated (\(updated.count) window(s))", logger: AppLog.windowState)
            onWindowsChanged?()
        }
    }

    private func beginTimedRefresh(label: String, sequence: Int) -> UInt64 {
#if DEBUG
        _ = label
        _ = sequence
        return DispatchTime.now().uptimeNanoseconds
#else
        _ = label
        _ = sequence
        return 0
#endif
    }

    private func endTimedRefresh(label: String, sequence: Int, started: UInt64) {
#if DEBUG
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        let elapsedText = String(format: "%.2f", elapsedMs)
        AppLog.debug(
            "Refresh #\(sequence) \(label) took \(elapsedText)ms",
            logger: AppLog.windowState
        )
#else
        _ = label
        _ = sequence
        _ = started
#endif
    }

    private func describe(_ flags: DirtyFlags) -> String {
        var labels: [String] = []
        if flags.contains(.full) { labels.append("full") }
        if flags.contains(.focus) { labels.append("focus") }
        if flags.contains(.appWindows) { labels.append("appWindows") }
        return labels.isEmpty ? "none" : labels.joined(separator: "+")
    }

    private func describePids(_ pids: Set<pid_t>) -> String {
        guard !pids.isEmpty else { return "-" }
        return pids
            .map(String.init)
            .sorted()
            .joined(separator: ",")
    }

    func debugText() -> String {
        guard !windows.isEmpty else {
            return "Windows\n- No on-screen app windows"
        }

        var lines = ["Windows (\(windows.count))"]

        for (index, window) in windows.enumerated() {
            lines.append("- #\(index + 1): \(window.ownerName) [pid \(window.ownerPID)]\(window.isFocused ? " FOCUSED" : "")")
            lines.append("  title:   \(window.title)")
            lines.append("  monitor: \(window.monitorName ?? "unknown")")
            lines.append("  space:   \(window.spaceID.map(String.init) ?? "unknown")")
            lines.append("  bounds:  \(rectDescription(window.bounds))")
            lines.append("  id:      \(window.windowNumber)")
        }

        return lines.joined(separator: "\n")
    }

    private func focusedWindowDescriptor(frontmostPID: pid_t?) -> FocusedWindowDescriptor? {
        guard AccessibilityPermissionManager.shared.isAccessibilityGranted(),
              let frontmostPID else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostPID)
        var focusedWindowValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard focusedResult == .success,
              let focusedWindowValue else {
            return nil
        }

        let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        let title = copyAXString(focusedWindow, attribute: kAXTitleAttribute as CFString)

        var frame: NSRect?
        if let position = copyAXPoint(focusedWindow, attribute: kAXPositionAttribute as CFString),
           let size = copyAXSize(focusedWindow, attribute: kAXSizeAttribute as CFString) {
            frame = NSRect(origin: position, size: size)
        }

        return FocusedWindowDescriptor(title: title, frame: frame)
    }

    private func matchesFocusedWindow(title: String, bounds: NSRect, focused: FocusedWindowDescriptor?) -> Bool {
        guard let focused else {
            return false
        }

        if let focusedTitle = focused.title, focusedTitle == title {
            return true
        }

        if let focusedFrame = focused.frame {
            return abs(focusedFrame.origin.x - bounds.origin.x) < 2
                && abs(focusedFrame.origin.y - bounds.origin.y) < 2
                && abs(focusedFrame.size.width - bounds.size.width) < 2
                && abs(focusedFrame.size.height - bounds.size.height) < 2
        }

        return false
    }

    private func monitorName(for windowBounds: NSRect) -> String? {
        let center = NSPoint(x: windowBounds.midX, y: windowBounds.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen.localizedName
        }

        var best: (name: String, area: CGFloat)?
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(windowBounds)
            let area = overlap.width * overlap.height
            if area <= 0 {
                continue
            }

            if let best, best.area >= area {
                continue
            }

            best = (screen.localizedName, area)
        }

        return best?.name
    }

    private func copyAXString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else {
            return nil
        }

        return value as? String
    }

    private func copyAXPoint(_ element: AXUIElement, attribute: CFString) -> NSPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint,
              AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return NSPoint(x: point.x, y: point.y)
    }

    private func copyAXSize(_ element: AXUIElement, attribute: CFString) -> NSSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize,
              AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return NSSize(width: size.width, height: size.height)
    }

    private func rectDescription(_ rect: NSRect) -> String {
        "x=\(Int(rect.origin.x)), y=\(Int(rect.origin.y)), w=\(Int(rect.size.width)), h=\(Int(rect.size.height))"
    }

}

private extension WindowStateStore.WindowSnapshot {
    func withFocused(_ focused: Bool) -> Self {
        WindowStateStore.WindowSnapshot(
            windowNumber: windowNumber,
            ownerName: ownerName,
            ownerPID: ownerPID,
            bundleID: bundleID,
            title: title,
            bounds: bounds,
            monitorName: monitorName,
            spaceID: spaceID,
            isFocused: focused
        )
    }
}
