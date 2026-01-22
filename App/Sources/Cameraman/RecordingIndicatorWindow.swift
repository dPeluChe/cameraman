//
//  RecordingIndicatorWindow.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import AppKit

/// Floating window that shows "REC" indicator during recording
@MainActor
class RecordingIndicatorWindow: NSObject {
    private var window: NSWindow?
    private var blinkTimer: Timer?
    private var isVisible = true

    func show() {
        guard let mainScreen = NSScreen.main else { return }

        // Create a small window in the top-right corner
        let windowWidth: CGFloat = 100
        let windowHeight: CGFloat = 40
        let padding: CGFloat = 20

        let windowFrame = NSRect(
            x: mainScreen.frame.maxX - windowWidth - padding,
            y: mainScreen.frame.maxY - windowHeight - padding,
            width: windowWidth,
            height: windowHeight
        )

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false

        // Create content view with "REC" label
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))

        // Background
        let backgroundBox = NSBox(frame: containerView.bounds)
        backgroundBox.boxType = .custom
        backgroundBox.isTransparent = true
        backgroundBox.fillColor = NSColor.red.withAlphaComponent(0.9)
        backgroundBox.cornerRadius = 8
        containerView.addSubview(backgroundBox)

        // "REC" label
        let label = NSTextField(frame: containerView.bounds)
        label.stringValue = "● REC"
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        label.alignment = .center
        containerView.addSubview(label)

        window.contentView = containerView
        window.orderFrontRegardless()

        self.window = window

        // Start blinking animation
        isVisible = true
        blinkTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(handleBlinkTimer(_:)), userInfo: nil, repeats: true)
    }

    @objc private func handleBlinkTimer(_ timer: Timer) {
        isVisible.toggle()
        window?.alphaValue = isVisible ? 1.0 : 0.5
    }

    func hide() {
        blinkTimer?.invalidate()
        blinkTimer = nil

        if let window = window {
            window.orderOut(nil)
            window.close()
            self.window = nil
        }
    }
}
