//
// SwiftUI app entrypoint that delegates lifecycle handling to AppDelegate for headless accessory behavior.

import SwiftUI

@main
struct window_managerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
