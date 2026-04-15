import AppKit
import Foundation

enum Configuration {
    /// App bundle IDs that should be automatically managed and resized to full screen.
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
    static let stageOffset: CGFloat = 10000

    /// Hotkey definitions
    enum HotKeys {
        static let modifiers: NSEvent.ModifierFlags = [.option]
        static let moveModifiers: NSEvent.ModifierFlags = [.option, .shift]

        static let status = "s"
        static let debug = "a"
        static let managedToggle = "m"
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
