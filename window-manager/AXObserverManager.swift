import AppKit

@MainActor
final class AXObserverManager {
    private var appObservers: [pid_t: AppObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isWatching = false
    
    // Route these to your WindowStateStore cache
    var handleWindowCreated: ((AXUIElement, pid_t) -> Void)?
    var handleWindowFocused: ((AXUIElement, pid_t) -> Void)?
    var handleWindowDestroyed: ((AXUIElement, pid_t) -> Void)?

    func startWatching() {
        guard !isWatching else {
            return
        }
        isWatching = true

        // 1. Bootstrap currently running apps
        for app in NSWorkspace.shared.runningApplications {
            attachObserver(to: app.processIdentifier)
        }

        // 2. Watch for future app lifecycle events
        let nc = NSWorkspace.shared.notificationCenter
        
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.attachObserver(to: app.processIdentifier)
                }
            }
        )
        
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.detachObserver(from: app.processIdentifier)
                }
            }
        )
    }

    func stopWatching() {
        guard isWatching else {
            return
        }
        isWatching = false

        let nc = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            nc.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for observer in appObservers.values {
            observer.stop()
        }
        appObservers.removeAll()
    }

    private func attachObserver(to pid: pid_t) {
        guard appObservers[pid] == nil else { return }
        
        let observer = AppObserver(pid: pid)
        
        observer.onWindowCreated = { [weak self] element in
            self?.handleWindowCreated?(element, pid)
        }
        observer.onWindowFocused = { [weak self] element in
            self?.handleWindowFocused?(element, pid)
        }
        observer.onWindowDestroyed = { [weak self] element in
            self?.handleWindowDestroyed?(element, pid)
        }
        
        observer.start()
        appObservers[pid] = observer
    }

    private func detachObserver(from pid: pid_t) {
        appObservers[pid]?.stop()
        appObservers.removeValue(forKey: pid)
    }
}