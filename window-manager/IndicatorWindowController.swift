//
// Manages the temporary center-screen non-interactive indicator panel and toggle behavior.

import AppKit
import Foundation

@MainActor
final class IndicatorWindowController {
    private let fontSize: CGFloat = 15
    private let horizontalPadding: CGFloat = 26
    private let verticalPadding: CGFloat = 18

    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?
    private var isVisible = false

    func show(text: String, duration: TimeInterval? = 1.25) {
        hideTask?.cancel()
        AppLog.debug("Showing indicator: \(text)", logger: AppLog.indicator)
        render(text: text)
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

    func toggle(text: String) {
        if isVisible {
            AppLog.debug("Hiding indicator via toggle", logger: AppLog.indicator)
            hide()
        } else {
            show(text: text, duration: nil)
        }
    }

    func updateIfVisible(text: String) {
        guard isVisible else {
            return
        }

        AppLog.debug("Updating visible indicator", logger: AppLog.indicator)
        render(text: text)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        isVisible = false
    }

    private func render(text: String) {
        let panel = panel ?? makePanel()
        let label = makeLabel(text: text)

        panel.contentView = label
        panel.setFrame(centeredFrame(for: panel, size: label.fittingSize), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
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