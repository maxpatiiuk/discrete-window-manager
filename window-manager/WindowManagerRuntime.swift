//
//  WindowManagerRuntime.swift
//  window-manager
//
//  Created by GitHub Copilot on 2026-04-14.
//

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let indicatorController = IndicatorWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.info("App launched in accessory mode")

        let hasAccessibility = AccessibilityPermissionManager.shared
            .requestAccessibilityPermission(prompt: true)

        if hasAccessibility {
            AppLog.info("Accessibility permission is granted", logger: AppLog.accessibility)
            indicatorController.show(text: "Window manager ready")
        } else {
            AppLog.error("Accessibility permission is missing", logger: AppLog.accessibility)
            indicatorController.show(text: "Enable Accessibility permission")
        }
    }
}

enum AccessibilityPermissionManager {
    static let shared = AccessibilityPermissionManager.self

    static func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}

@MainActor
final class IndicatorWindowController {
    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?

    func show(text: String, duration: TimeInterval = 1.25) {
        hideTask?.cancel()
        AppLog.debug("Showing indicator: \(text)", logger: AppLog.indicator)

        let panel = panel ?? makePanel()
        let label = makeLabel(text: text)

        panel.contentView = label
        panel.setFrame(centeredFrame(for: panel, size: label.fittingSize), display: true)
        panel.orderFrontRegardless()

        self.panel = panel

        let task = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        return panel
    }

    private func makeLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        label.isBezeled = false
        label.drawsBackground = true
        label.wantsLayer = true
        label.layer?.cornerRadius = 16
        label.layer?.masksToBounds = true

        let horizontalPadding: CGFloat = 28
        let verticalPadding: CGFloat = 16
        let size = label.intrinsicContentSize
        label.frame = NSRect(
            x: 0,
            y: 0,
            width: size.width + horizontalPadding * 2,
            height: size.height + verticalPadding * 2
        )

        return label
    }

    private func centeredFrame(for panel: NSPanel, size: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}