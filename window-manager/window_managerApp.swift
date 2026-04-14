//
//  window_managerApp.swift
//  window-manager
//
//  Created by Max Patiiuk on 2026-04-14.
//

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
