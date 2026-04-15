//
// Manages the temporary center-screen non-interactive indicator panel and toggle behavior.

import AppKit
import Foundation

@MainActor
final class IndicatorWindowController {
    private let fontSize: CGFloat = 15
    private let horizontalPadding: CGFloat = 26
    private let verticalPadding: CGFloat = 18

    private var panels: [String: NSPanel] = [:] // screenID -> panel
    private var hideTask: DispatchWorkItem?
    private(set) var isVisible = false

    func show(textsByScreenID: [String: String], duration: TimeInterval? = 1.25) {
        hideTask?.cancel()
        render(textsByScreenID: textsByScreenID)
        isVisible = true

        guard let duration else {
            return
        }

        let task = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    func show(text: String, duration: TimeInterval? = 1.25) {
        // Fallback for simple messages
        let texts = NSScreen.screens.reduce(into: [String: String]()) { acc, screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")].map { String(describing: $0) } ?? "unknown"
            acc[id] = text
        }
        show(textsByScreenID: texts, duration: duration)
    }

    func toggle(textsByScreenID: [String: String]) {
        if isVisible {
            AppLog.debug("Hiding indicators via toggle", logger: AppLog.indicator)
            hide()
        } else {
            show(textsByScreenID: textsByScreenID, duration: nil)
        }
    }

    func updateIfVisible(textsByScreenID: [String: String]) {
        guard isVisible else {
            return
        }

        render(textsByScreenID: textsByScreenID)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        for panel in panels.values {
            panel.orderOut(nil)
        }
        isVisible = false
    }

    private func render(textsByScreenID: [String: String]) {
        // Clean up panels for screens that no longer exist
        let screenIDs = Set(textsByScreenID.keys)
        for id in panels.keys where !screenIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
        }

        var previousText = ""
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")].map { String(describing: $0) } ?? "unknown"
            guard let text = textsByScreenID[id] else { continue }

            let panel = panels[id] ?? makePanel()
            let label = makeLabel(text: text)

            if previousText != text {
                AppLog.debug(text, logger: AppLog.indicator)
                previousText = text
            }

            panel.contentView = label
            panel.setFrame(centeredFrame(for: panel, screen: screen, size: label.fittingSize), display: true)
            panel.orderFrontRegardless()

            panels[id] = panel
        }
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
        label.alignment = .left
        label.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        label.isBezeled = false
        label.drawsBackground = true
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.usesSingleLineMode = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 16
        label.layer?.masksToBounds = true

        let size = measuredTextSize(text)
        label.frame = NSRect(
            x: 0,
            y: 0,
            width: size.width + horizontalPadding * 2,
            height: size.height + verticalPadding * 2
        )

        return label
    }

    private func measuredTextSize(_ text: String) -> NSSize {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longestLineLength = lines.map(\.count).max() ?? 0
        let lineCount = max(lines.count, 1)

        let characterWidth = ("0" as NSString).size(withAttributes: attributes).width
        let lineHeight = font.ascender - font.descender + font.leading

        let width = min(max(CGFloat(longestLineLength) * characterWidth, 280), 980)
        let height = min(max(CGFloat(lineCount) * lineHeight, 48), 700)

        return NSSize(width: width, height: height)
    }

    private func centeredFrame(for panel: NSPanel, screen: NSScreen, size: NSSize) -> NSRect {
        let screenFrame = screen.visibleFrame
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}