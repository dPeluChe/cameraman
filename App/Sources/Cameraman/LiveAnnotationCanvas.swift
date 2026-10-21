//
//  LiveAnnotationCanvas.swift
//  App
//
//  Transparent view over the recorded display where the presenter draws while recording.
//  Everything here is real on-screen content, so the screen capture records it as it is.
//

import AppKit
import SwiftUI
import EngineKit

/// Top-left origin so normalized points map straight to view points.
final class LiveAnnotationCanvasView: NSView {
    weak var controller: LiveAnnotationController?

    private var draft: LiveAnnotation?
    private var visible: [LiveAnnotation] = []
    private var laserTrail: [(point: CGPoint, time: TimeInterval)] = []
    private var laserTimer: Timer?
    private var blurViews: [UUID: NSVisualEffectView] = [:]
    private var textField: NSTextField?

    private static let laserLife: TimeInterval = 0.9

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard let tool = controller?.tool, tool != .pointer else { return }
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    override func updateTrackingAreas() {
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Model sync

    /// Rebuild what is shown from the controller's log (committed shapes and blur panes).
    func refresh() {
        visible = controller?.log.visible ?? []
        let blurs = visible.filter { $0.kind == .blur }
        let live = Set(blurs.map(\.id))
        for id in blurViews.keys where !live.contains(id) {
            blurViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        for blur in blurs where blurViews[blur.id] == nil {
            let view = NSVisualEffectView()
            view.material = .hudWindow
            view.blendingMode = .behindWindow
            view.state = .active
            view.frame = LiveAnnotationRenderer.frame(of: blur, in: bounds.size)
            addSubview(view, positioned: .below, relativeTo: textField)
            blurViews[blur.id] = view
        }
        needsDisplay = true
    }

    private func normalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x / bounds.width, 0), 1), y: min(max(p.y / bounds.height, 0), 1))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for annotation in visible where LiveAnnotationRenderer.dirtyFrame(of: annotation, in: bounds.size).intersects(dirtyRect) {
            LiveAnnotationRenderer.draw(annotation, in: bounds.size)
        }
        if let draft {
            if draft.kind == .blur {
                let rect = LiveAnnotationRenderer.frame(of: draft, in: bounds.size)
                NSColor.white.withAlphaComponent(0.15).setFill()
                rect.fill()
                let outline = NSBezierPath(rect: rect)
                outline.setLineDash([6, 4], count: 2, phase: 0)
                NSColor.white.setStroke()
                outline.stroke()
            } else {
                LiveAnnotationRenderer.draw(draft, in: bounds.size)
            }
        }
        drawLaser()
    }

    private func drawLaser() {
        let now = ProcessInfo.processInfo.systemUptime
        let color = LiveAnnotationRenderer.color(controller?.colorHex ?? "#FF3B30")
        for (index, sample) in laserTrail.enumerated() {
            let age = (now - sample.time) / Self.laserLife
            let isHead = index == laserTrail.count - 1
            let radius = isHead ? 11.0 : 8.0 * (1 - age) + 2
            color.withAlphaComponent(isHead ? 0.9 : 0.55 * (1 - age)).setFill()
            NSBezierPath(ovalIn: CGRect(x: sample.point.x - radius, y: sample.point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        guard controller?.tool == .laser else { return }
        addLaserPoint(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        commitText()
        let p = convert(event.locationInWindow, from: nil)
        switch controller.tool {
        case .pointer: break
        case .laser: addLaserPoint(p)
        case .text: beginText(at: p)
        default:
            guard let kind = controller.tool.shapeKind else { return }
            draft = LiveAnnotation(kind: kind, points: [normalized(p)], colorHex: controller.colorHex,
                                   lineWidth: controller.lineWidth, start: controller.elapsed)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if controller?.tool == .laser { addLaserPoint(p); return }
        guard var draft else { return }
        let point = normalized(p)
        if draft.kind == .pen {
            draft.points.append(point)
        } else {
            draft.points = [draft.points[0], point]
        }
        setNeedsDisplay(LiveAnnotationRenderer.dirtyFrame(of: self.draft ?? draft, in: bounds.size).union(LiveAnnotationRenderer.dirtyFrame(of: draft, in: bounds.size)))
        self.draft = draft
    }

    override func mouseUp(with event: NSEvent) {
        guard let draft else { return }
        self.draft = nil
        controller?.commit(draft)
        setNeedsDisplay(LiveAnnotationRenderer.dirtyFrame(of: draft, in: bounds.size))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            cancelText()
            controller?.tool = .pointer
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            controller?.undo()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Laser

    private func addLaserPoint(_ p: CGPoint) {
        let before = laserBounds()
        let now = ProcessInfo.processInfo.systemUptime
        // Mouse events arrive faster than the eye can tell apart: keep the trail sparse.
        if let last = laserTrail.last, hypot(last.point.x - p.x, last.point.y - p.y) < 4 {
            laserTrail[laserTrail.count - 1] = (p, now)
        } else {
            laserTrail.append((p, now))
        }
        setNeedsDisplay(before.union(laserBounds()))
        guard laserTimer == nil else { return }
        laserTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLaser() }
        }
    }

    private func tickLaser() {
        let before = laserBounds()
        let now = ProcessInfo.processInfo.systemUptime
        laserTrail.removeAll { now - $0.time > Self.laserLife }
        setNeedsDisplay(before)
        if laserTrail.isEmpty { stopLaser() }
    }

    private func laserBounds() -> CGRect {
        guard let first = laserTrail.first else { return .null }
        let box = laserTrail.reduce(CGRect(origin: first.point, size: .zero)) { $0.union(CGRect(origin: $1.point, size: .zero)) }
        return box.insetBy(dx: -16, dy: -16)
    }

    func stopLaser() {
        let before = laserBounds()
        laserTimer?.invalidate()
        laserTimer = nil
        laserTrail.removeAll()
        if !before.isNull { setNeedsDisplay(before) }
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        guard let controller else { return }
        let size = CGFloat(LiveAnnotation.textPointSize(forLineWidth: controller.lineWidth))
        let field = NSTextField(frame: CGRect(x: p.x, y: p.y, width: 320, height: size + 10))
        field.font = .systemFont(ofSize: size, weight: .bold)
        field.textColor = LiveAnnotationRenderer.color(controller.colorHex)
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "Texto"
        field.target = self
        field.action = #selector(commitText)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitText() {
        guard let field = textField, let controller else { return }
        textField = nil
        let text = field.stringValue
        let origin = field.frame.origin
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        controller.commit(LiveAnnotation(kind: .text, points: [normalized(origin)], colorHex: controller.colorHex,
                                         lineWidth: controller.lineWidth, text: text, start: controller.elapsed))
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
    }

    func toolChanged() {
        commitText()
        draft = nil
        stopLaser()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}
