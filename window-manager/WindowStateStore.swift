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
        let windowID: Int?
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
    var currentMonitors: [MonitorStateStore.MonitorSnapshot] = []

    private let axManager = AXObserverManager()
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var dirtyFlags: DirtyFlags = []
    private var dirtyPIDs: Set<pid_t> = []
    private var refreshSequence = 0

    func startWatching() {
        refresh()
        axManager.handleWindowCreated = { [weak self] _, pid in Task { @MainActor [weak self] in self?.requestRefresh(flags: [.appWindows], pids: [pid]) } }
        axManager.handleWindowFocused = { [weak self] _, _ in Task { @MainActor [weak self] in self?.requestRefresh(flags: [.focus]) } }
        axManager.handleWindowDestroyed = { [weak self] _, pid in Task { @MainActor [weak self] in self?.requestRefresh(flags: [.appWindows], pids: [pid]) } }
        axManager.startWatching()

        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.requestRefresh(flags: [.focus]) } })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in if let pid { self?.requestRefresh(flags: [.appWindows, .focus], pids: [pid]) } else { self?.requestRefresh(flags: [.full]) } }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.requestRefresh(flags: [.full]) } })
        AppLog.debug("Started event-driven window state watcher", logger: AppLog.windowState)
    }

    func stopWatching() {
        refreshTask?.cancel()
        refreshTask = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        axManager.stopWatching()
        AppLog.debug("Stopped window state watcher", logger: AppLog.windowState)
    }

    private func requestRefresh(flags: DirtyFlags, pids: Set<pid_t> = []) {
        dirtyFlags.formUnion(flags)
        dirtyPIDs.formUnion(pids)
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled else { return }
            self.processPendingRefresh()
        }
    }

    func refresh() { requestRefresh(flags: [.full]) }

    private func processPendingRefresh() {
        refreshSequence += 1
        let pendingFlags = dirtyFlags
        let pendingPIDs = dirtyPIDs
        dirtyFlags = []
        dirtyPIDs.removeAll()
        Task { @MainActor in
            if pendingFlags.contains(.full) { await fullRefresh() }
            else if pendingFlags.contains(.appWindows), !pendingPIDs.isEmpty { await refreshDirtyApps(pids: pendingPIDs) }
            else if pendingFlags.contains(.focus) { applyFocusUpdateOnly() }
        }
    }

    private func fullRefresh() async {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)
        guard let raw = copyVisibleWindowInfo() else { return }
        let updated = await buildSnapshots(from: raw, limitingPIDs: nil, frontmostPID: frontmostPID, focusedDescriptor: focusedDescriptor, existingWindows: [])
        applyWindowsIfChanged(updated)
    }

    private func refreshDirtyApps(pids: Set<pid_t>) async {
        guard !pids.isEmpty, let raw = copyVisibleWindowInfo() else { return }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)
        let updated = await buildSnapshots(from: raw, limitingPIDs: pids, frontmostPID: frontmostPID, focusedDescriptor: focusedDescriptor, existingWindows: windows)
        applyWindowsIfChanged(updated)
    }

    private func applyFocusUpdateOnly() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedDescriptor = focusedWindowDescriptor(frontmostPID: frontmostPID)
        let updated = applyingFocusMarkers(to: windows, frontmostPID: frontmostPID, focusedDescriptor: focusedDescriptor)
        applyWindowsIfChanged(updated)
    }

    private func copyVisibleWindowInfo() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    }

    private struct AXWindowMap: @unchecked Sendable {
        let windows: [Int: AXUIElement]
    }

    private func buildSnapshots(
        from raw: [[String: Any]],
        limitingPIDs: Set<pid_t>?,
        frontmostPID: pid_t?,
        focusedDescriptor: FocusedWindowDescriptor?,
        existingWindows: [WindowSnapshot]
    ) async -> [WindowSnapshot] {
        var prefix: [WindowSnapshot] = []
        if let limitingPIDs { prefix = existingWindows.filter { !limitingPIDs.contains($0.ownerPID) } }
        
        let pidsToScan = Set(raw.compactMap { info -> pid_t? in
            guard let ownerPIDRaw = info[kCGWindowOwnerPID as String] as? Int else { return nil }
            let pid = pid_t(ownerPIDRaw)
            if let limitingPIDs, !limitingPIDs.contains(pid) { return nil }
            return pid
        })

        // Pre-fetch all window maps in parallel to avoid blocking on slow apps
        let appWindowsCache = await withTaskGroup(of: (pid_t, AXWindowMap).self) { group in
            for pid in pidsToScan {
                let app = NSRunningApplication(processIdentifier: pid)
                if app?.activationPolicy != .regular { continue }
                group.addTask {
                    let appElement = AXUIElementCreateApplication(pid)
                    var windowsValue: CFTypeRef?
                    var windowDict: [Int: AXUIElement] = [:]
                    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                       let axWindows = windowsValue as? [AXUIElement] {
                        for axWin in axWindows {
                            var idValue: CGWindowID = 0
                            _ = _AXUIElementGetWindow(axWin, &idValue)
                            windowDict[Int(idValue)] = axWin
                        }
                    }
                    return (pid, AXWindowMap(windows: windowDict))
                }
            }
            var cache: [pid_t: AXWindowMap] = [:]
            for await (pid, map) in group {
                cache[pid] = map
            }
            return cache
        }

        var extracted: [WindowSnapshot] = []
        var appCache: [pid_t: (bundleID: String?, isRegular: Bool)] = [:]
        
        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let ownerPIDRaw = info[kCGWindowOwnerPID as String] as? Int,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let pid = pid_t(ownerPIDRaw)
            if let limitingPIDs, !limitingPIDs.contains(pid) { continue }
            if cgBounds.width < 100 || cgBounds.height < 100 { continue }
            let appInfo = appCache[pid] ?? {
                let app = NSRunningApplication(processIdentifier: pid)
                let info = (bundleID: app?.bundleIdentifier, isRegular: app?.activationPolicy == .regular)
                appCache[pid] = info
                return info
            }()
            if !appInfo.isRegular { continue }
            
            guard let axWindows = appWindowsCache[pid]?.windows, let element = axWindows[number] else { continue }
            var value: CFTypeRef?
            let isStandard = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) != .success || {
                guard let subrole = value as? String else { return true }
                return !Configuration.ignoredWindowSubroles.contains(subrole)
            }()
            if !isStandard { continue }
            
            // Allow other events to be processed between window processing
            await Task.yield()

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "<untitled>"
            let monitorName = monitorName(for: cgBounds)
            let spaceID = (info["kCGWindowWorkspace"] as? NSNumber)?.intValue
            extracted.append(WindowSnapshot(
                windowNumber: number, ownerName: ownerName, ownerPID: pid, bundleID: appInfo.bundleID,
                title: title, bounds: cgBounds, monitorName: monitorName, spaceID: spaceID, isFocused: false
            ))
        }
        let merged = prefix + extracted
        let withFocus = applyingFocusMarkers(to: merged, frontmostPID: frontmostPID, focusedDescriptor: focusedDescriptor)
        return sortByCurrentZOrder(withFocus, raw: raw)
    }

    private func sortByCurrentZOrder(_ snapshots: [WindowSnapshot], raw: [[String: Any]]) -> [WindowSnapshot] {
        var zIndexByWindowID: [Int: Int] = [:]
        for (index, info) in raw.enumerated() { if let number = info[kCGWindowNumber as String] as? Int { zIndexByWindowID[number] = index } }
        return snapshots.sorted { (zIndexByWindowID[$0.windowNumber] ?? Int.max) < (zIndexByWindowID[$1.windowNumber] ?? Int.max) }
    }

    private func applyingFocusMarkers(to snapshots: [WindowSnapshot], frontmostPID: pid_t?, focusedDescriptor: FocusedWindowDescriptor?) -> [WindowSnapshot] {
        guard !snapshots.isEmpty else { return snapshots }
        var mutable = snapshots
        var focusedFound = false
        for index in mutable.indices {
            let snapshot = mutable[index]
            let shouldFocus = !focusedFound && snapshot.ownerPID == frontmostPID && matchesFocusedWindow(windowNumber: snapshot.windowNumber, title: snapshot.title, bounds: snapshot.bounds, focused: focusedDescriptor)
            if shouldFocus {
                mutable[index] = snapshot.withFocused(true)
                focusedFound = true
            } else if snapshot.isFocused {
                mutable[index] = snapshot.withFocused(false)
            }
        }
        return mutable
    }

    private func applyWindowsIfChanged(_ updated: [WindowSnapshot]) {
        if updated != windows {
            windows = updated
            AppLog.debug("Window topology updated (\(updated.count) window(s))", logger: AppLog.windowState)
            onWindowsChanged?()
        }
        #if DEBUG
        if let focused = updated.first(where: { $0.isFocused }) {
            AppLog.debug("OS reports focus on window \(focused.windowNumber) (\(focused.ownerName)) on monitor \(focused.monitorName ?? "unknown")", logger: AppLog.windowState)
        }
        #endif
    }

    func debugText() -> String {
        guard !windows.isEmpty else { return "Windows\n- No on-screen app windows" }
        var lines = ["Windows (\(windows.count))"]
        for (index, window) in windows.enumerated() {
            lines.append("- #\(index + 1): \(window.ownerName) [pid \(window.ownerPID)]\(window.isFocused ? " FOCUSED" : "")")
            lines.append("  title:   \(window.title)\n  monitor: \(window.monitorName ?? "unknown")\n  bounds:  \(rectDescription(window.bounds))\n  id:      \(window.windowNumber)")
        }
        return lines.joined(separator: "\n")
    }

    private func focusedWindowDescriptor(frontmostPID: pid_t?) -> FocusedWindowDescriptor? {
        guard AccessibilityPermissionManager.shared.isAccessibilityGranted(), let frontmostPID else { return nil }
        let appElement = AXUIElementCreateApplication(frontmostPID)
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
              let focusedWindowValue else { return nil }
        let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(focusedWindow, &windowID)
        let title = copyAXString(focusedWindow, attribute: kAXTitleAttribute as CFString)
        var frame: NSRect?
        if let pos = copyAXPoint(focusedWindow, attribute: kAXPositionAttribute as CFString), let size = copyAXSize(focusedWindow, attribute: kAXSizeAttribute as CFString) {
            frame = NSRect(origin: pos, size: size)
        }
        return FocusedWindowDescriptor(windowID: Int(windowID), title: title, frame: frame)
    }

    private func matchesFocusedWindow(windowNumber: Int, title: String, bounds: NSRect, focused: FocusedWindowDescriptor?) -> Bool {
        guard let focused else { return false }
        if abs(bounds.origin.x) >= Configuration.visibleThreshold { return false }
        if let targetID = focused.windowID, targetID > 0 { return windowNumber == targetID }
        if let focusedTitle = focused.title, focusedTitle != title { return false }
        if let focusedFrame = focused.frame {
            return abs(focusedFrame.origin.x - bounds.origin.x) < 5 && abs(focusedFrame.origin.y - bounds.origin.y) < 5 && abs(focusedFrame.size.width - bounds.size.width) < 5 && abs(focusedFrame.size.height - bounds.size.height) < 5
        }
        return focused.title == title
    }

    private func monitorName(for windowBounds: NSRect) -> String? {
        if abs(windowBounds.origin.x) >= Configuration.visibleThreshold { return nil }
        let center = NSPoint(x: windowBounds.midX, y: windowBounds.midY)
        if let monitor = currentMonitors.first(where: { $0.frame.contains(center) }) { return monitor.name }
        var best: (name: String, area: CGFloat)?
        for monitor in currentMonitors {
            let overlap = monitor.frame.intersection(windowBounds)
            let area = overlap.width * overlap.height
            if area > 0 && (best == nil || area > best!.area) { best = (monitor.name, area) }
        }
        return best?.name
    }

    private func copyAXString(_ e: AXUIElement, attribute a: CFString) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a, &v) == .success ? v as? String : nil
    }

    private func copyAXPoint(_ e: AXUIElement, attribute a: CFString) -> NSPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, a, &v) == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? NSPoint(x: p.x, y: p.y) : nil
    }

    private func copyAXSize(_ e: AXUIElement, attribute a: CFString) -> NSSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, a, &v) == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? NSSize(width: s.width, height: s.height) : nil
    }

    private func rectDescription(_ r: NSRect) -> String { "x=\(Int(r.origin.x)), y=\(Int(r.origin.y)), w=\(Int(r.size.width)), h=\(Int(r.size.height))" }
}

private extension WindowStateStore.WindowSnapshot {
    func withFocused(_ f: Bool) -> Self { WindowStateStore.WindowSnapshot(windowNumber: windowNumber, ownerName: ownerName, ownerPID: ownerPID, bundleID: bundleID, title: title, bounds: bounds, monitorName: monitorName, spaceID: spaceID, isFocused: f) }
}

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
