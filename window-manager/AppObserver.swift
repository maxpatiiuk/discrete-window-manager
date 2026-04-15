import AppKit
import ApplicationServices

/// Wraps AXObserver for a single process.
/// Manages the C-bridge and translates raw AX events into Swift closures.
final class AppObserver {
    let pid: pid_t
    private var axObserver: AXObserver?
    private var trackedWindowElementHashes: Set<Int> = []
    
    // Callbacks to your main store
    var onWindowCreated: ((AXUIElement) -> Void)?
    var onWindowFocused: ((AXUIElement) -> Void)?
    var onWindowDestroyed: ((AXUIElement) -> Void)?

    init(pid: pid_t) {
        self.pid = pid
    }

    func start() {
        // 1. Create the C-Callback Bridge
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        var observerRaw: AXObserver?
        let error = AXObserverCreate(pid, observerCallback, &observerRaw)
        
        guard error == .success, let observer = observerRaw else {
            return // App likely lacks accessibility privileges or died
        }
        
        self.axObserver = observer

        // 2. Register for specific Edge-Triggers
        let appElement = AXUIElementCreateApplication(pid)
        
        let notifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString
        ]
        
        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification, refcon)
        }

        // 3. Attach to the Main Run Loop (Mandatory for AXObserver to fire)
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            CFRunLoopMode.defaultMode
        )
    }

    func stop() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            CFRunLoopMode.defaultMode
        )
        self.axObserver = nil
    }

    deinit {
        stop()
    }
    
    // 4. The strongly-typed internal handler
    fileprivate func handleEvent(element: AXUIElement, notification: CFString) {
        // AXCallbacks fire on the thread of the RunLoop they were attached to (Main).
        // Safely route to closures.
        switch notification as String {
        case kAXWindowCreatedNotification:
            guard isWindowLikeElement(element) else {
                return
            }
            trackedWindowElementHashes.insert(elementHash(element))
            onWindowCreated?(element)
        case kAXFocusedWindowChangedNotification:
            guard isWindowLikeElement(element) else {
                return
            }
            trackedWindowElementHashes.insert(elementHash(element))
            onWindowFocused?(element)
        case kAXUIElementDestroyedNotification:
            let hash = elementHash(element)
            let wasTrackedWindow = trackedWindowElementHashes.remove(hash) != nil
            guard wasTrackedWindow else {
                return
            }
            onWindowDestroyed?(element)
        default:
            break
        }
    }

    private func isWindowLikeElement(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String else {
            return false
        }

        return role == kAXWindowRole
            || role == kAXSheetRole
            || role == "AXDialog"
    }

    private func elementHash(_ element: AXUIElement) -> Int {
        Int(CFHash(element))
    }
}

// Callback
// Must be a top-level or static function to bridge to C.
private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon = refcon else { return }
    
    // Cast the raw C-pointer back to the Swift instance
    let observerInstance = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
    observerInstance.handleEvent(element: element, notification: notification)
}