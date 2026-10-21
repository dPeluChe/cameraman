//
//  LiveAnnotationController.swift
//  App
//
//  Draw on the screen while recording: a click-through canvas over the recorded display plus a
//  small floating toolbar. The canvas is ordinary screen content, so the capture records it; the
//  toolbar is left out of the capture. The log of what was drawn is kept for post-production.
//

import AppKit
import Combine
import SwiftUI
import EngineKit

@MainActor
final class LiveAnnotationController: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case pointer, laser, pen, arrow, rect, ellipse, text, blur
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pointer: return "cursorarrow"
            case .laser: return "dot.circle.and.hand.point.up.left.fill"
            case .pen: return "pencil.tip"
            case .arrow: return "arrow.up.right"
            case .rect: return "rectangle"
            case .ellipse: return "circle"
            case .text: return "textformat"
            case .blur: return "drop.halffull"
            }
        }

        var title: String {
            switch self {
            case .pointer: return "Mouse (click through)"
            case .laser: return "Laser pointer"
            case .pen: return "Pen"
            case .arrow: return "Arrow"
            case .rect: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .text: return "Text"
            case .blur: return "Blur area"
            }
        }
    }

    static let palette = ["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF"]
    static let widths: [Double] = [3, 5, 9]

    @Published var tool: Tool = .pointer {
        didSet {
            guard tool != oldValue else { return }
            canvasPanel?.ignoresMouseEvents = tool == .pointer
            if tool != .pointer { canvasPanel?.makeKey() }
            canvasView?.toolChanged()
        }
    }
    @Published var colorHex = palette[0]
    @Published var lineWidth = widths[1]
    @Published private(set) var log = LiveAnnotationLog()

    private var canvasPanel: NSPanel?
    private var canvasView: LiveAnnotationCanvasView?
    private var toolbarPanel: NSPanel?
    private var clock = RecordingClock()

    /// Seconds into the recording, not counting paused time.
    var elapsed: TimeInterval { clock.elapsed() }

    /// CGWindowIDs the capture must leave out. The canvas is not in the list: it is the point.
    var excludedWindowIDs: [UInt32] { toolbarPanel.map { [UInt32($0.windowNumber)] } ?? [] }

    var canUndo: Bool { !log.visible.isEmpty }

    // MARK: Lifecycle

    /// Opens the canvas and toolbar on `screen`. Call before capture starts so the toolbar's
    /// window id can go in the exclusion list.
    func show(on screen: NSScreen) {
        let canvas = LiveAnnotationCanvasView(frame: CGRect(origin: .zero, size: screen.frame.size))
        canvas.controller = self
        let panel = AnnotationPanel(contentRect: screen.frame, key: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = canvas
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        canvasPanel = panel
        canvasView = canvas

        let host = NSHostingView(rootView: LiveAnnotationToolbar(controller: self))
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let toolbar = AnnotationPanel(contentRect: CGRect(origin: .zero, size: size), key: false)
        toolbar.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        toolbar.isMovableByWindowBackground = true
        toolbar.sharingType = .none
        toolbar.contentView = host
        toolbar.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 90))
        toolbar.orderFrontRegardless()
        toolbarPanel = toolbar
    }

    func startClock(at start: Date) { clock = RecordingClock(start: start) }
    func pauseClock() { clock.pause() }
    func resumeClock() { clock.resume() }

    /// Closes the windows and returns everything that was drawn.
    func finish() -> LiveAnnotationLog {
        canvasView?.stopLaser()
        log.clear(at: elapsed)
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        canvasPanel = nil
        canvasView = nil
        toolbarPanel = nil
        tool = .pointer
        return log
    }

    // MARK: Editing

    func commit(_ annotation: LiveAnnotation) {
        if log.add(annotation) { canvasView?.refresh() }
    }

    func undo() {
        guard log.undo(at: elapsed) else { return }
        canvasView?.refresh()
    }

    func clear() {
        log.clear(at: elapsed)
        canvasView?.refresh()
    }
}

/// Borderless transparent panel. The canvas can take key presses (Esc, ⌘Z, typing); the toolbar
/// never takes focus away from the app being demonstrated.
private final class AnnotationPanel: NSPanel {
    private let allowsKey: Bool

    init(contentRect: CGRect, key: Bool) {
        allowsKey = key
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
