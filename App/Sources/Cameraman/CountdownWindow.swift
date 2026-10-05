//
//  CountdownWindow.swift
//  App
//
//  Self-timer shown before a recording starts. It is a separate window that closes before
//  capture begins, so it never appears in the recording. Click it or press Esc to cancel.
//

import AppKit

@MainActor
final class CountdownWindow {
    /// Seconds the user can choose from; 0 means no timer.
    static let options = [0, 3, 5, 10]

    private var panel: CountdownPanel?
    private var continuation: CheckedContinuation<Bool, Never>?

    /// Counts down on screen. Returns false if the user cancelled.
    func run(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        let panel = CountdownPanel { [weak self] in self?.finish(completed: false) }
        self.panel = panel
        panel.show()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor [weak self] in
                for remaining in stride(from: seconds, to: 0, by: -1) {
                    guard let self, self.continuation != nil else { return }
                    panel.update(remaining)
                    try? await Task.sleep(for: .seconds(1))
                }
                self?.finish(completed: true)
            }
        }
    }

    private func finish(completed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.orderOut(nil)
        panel = nil
        continuation.resume(returning: completed)
    }
}

/// Borderless panel that can take key presses (for Esc) and mouse clicks.
private final class CountdownPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false

        let content = ClickView(frame: NSRect(x: 0, y: 0, width: 220, height: 220), onClick: onCancel)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        content.layer?.cornerRadius = 36
        label.font = .systemFont(ofSize: 110, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 40, width: 220, height: 130)
        content.addSubview(label)
        let hint = NSTextField(labelWithString: "Click or press Esc to cancel")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .white.withAlphaComponent(0.6)
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 14, width: 220, height: 16)
        content.addSubview(hint)
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    func show() {
        if let screen = NSScreen.main {
            setFrameOrigin(NSPoint(x: screen.frame.midX - 110, y: screen.frame.midY - 110))
        }
        makeKeyAndOrderFront(nil)
    }

    func update(_ remaining: Int) { label.stringValue = "\(remaining)" }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } else { super.keyDown(with: event) }  // 53 = Esc
    }
}

private final class ClickView: NSView {
    private let onClick: () -> Void
    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func mouseDown(with event: NSEvent) { onClick() }
}
