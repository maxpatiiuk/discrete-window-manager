import AppKit
import Foundation

enum Configuration {

    /// Only apps listed here will be automatically resized and managed.
    /// Add to this list any app you use commonly and verified for compatibility.
    /// You can get app bundle IDs using the script mentioned in the README.md
    static let managedAppBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.google.chrome.for.testing",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    /// Window subroles that should be ignored by the window manager.
    static let ignoredWindowSubroles: Set<String> = [
        kAXDialogSubrole,
        "AXSheet",
        "AXDrawer"
    ]

    /// The coordinate offset used to hide windows by moving them off-screen.
    /// This corresponds to lower right corner.
    static let stageOffset: CGFloat = 30000

    /// Threshold to determine if a window is on-screen or on the stage.
    static let visibleThreshold: CGFloat = 15000

    /// Hotkey definitions
    enum HotKeys {
        static let modifiers: NSEvent.ModifierFlags = [.option]
        static let moveModifiers: NSEvent.ModifierFlags = [.option, .shift]

        static let status = "s"
        static let debug = "a"
        static let managedToggle = "u"
        static let moveLeft = "h"
        static let moveRight = "l"

        static let leftScreenKeys = ["z", "x", "c", "v"]
        static let leftScreenCycle = "b"

        static let middleScreenKeys = ["q", "w", "e", "r"]
        static let middleScreenCycle = "t"
        
        static let rightScreenKeys = ["n", "m", ",", "."]
        static let rightScreenCycle = "0"
    }
}
