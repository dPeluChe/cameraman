//
//  LiveAnnotationRenderer.swift
//  App
//
//  Draws live annotations into the current graphics context (top-left origin).
//

import AppKit
import SwiftUI
import EngineKit

enum LiveAnnotationRenderer {
    private static var colors: [String: NSColor] = [:]
    private static let textShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }()

    /// Palette values are parsed once; draw runs per mouse event.
    static func color(_ hex: String) -> NSColor {
        if let cached = colors[hex] { return cached }
        let color = NSColor(Color(hex: hex))
        colors[hex] = color
        return color
    }

    /// Normalized shape bounds scaled to a view of `size`.
    static func frame(of annotation: LiveAnnotation, in size: CGSize) -> CGRect {
        let b = annotation.bounds
        return CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
    }

    /// Area a shape can paint, with room for the stroke, the arrow head and a text run's width.
    static func dirtyFrame(of annotation: LiveAnnotation, in size: CGSize) -> CGRect {
        var frame = frame(of: annotation, in: size)
        if annotation.kind == .text {
            let point = CGFloat(annotation.textPointSize)
            frame.size = CGSize(width: point * 0.8 * CGFloat((annotation.text ?? "").count), height: point * 1.5)
        }
        return frame.insetBy(dx: -40, dy: -40)
    }

    static func draw(_ annotation: LiveAnnotation, in size: CGSize) {
        let pts = annotation.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first else { return }
        let color = color(annotation.colorHex)
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch annotation.kind {
        case .pen:
            path.move(to: first)
            pts.dropFirst().forEach { path.line(to: $0) }
            path.stroke()
        case .arrow:
            guard let tip = pts.last, pts.count > 1 else { return }
            let head = arrowHead(from: first, to: tip, width: annotation.lineWidth)
            // The shaft stops at the head's base so the round cap does not poke through the tip.
            path.move(to: first)
            path.line(to: head.base)
            path.stroke()
            head.path.fill()
        case .rect:
            path.appendRoundedRect(frame(of: annotation, in: size), xRadius: 4, yRadius: 4)
            path.stroke()
        case .ellipse:
            path.appendOval(in: frame(of: annotation, in: size))
            path.stroke()
        case .blur:
            // The live blur is a visual-effect subview; only the draft outline is drawn by the canvas.
            break
        case .text:
            let font = NSFont.systemFont(ofSize: annotation.textPointSize, weight: .bold)
            (annotation.text ?? "").draw(at: first, withAttributes: [.font: font, .foregroundColor: color, .shadow: textShadow])
        }
    }

    private static func arrowHead(from tail: CGPoint, to tip: CGPoint, width: Double) -> (path: NSBezierPath, base: CGPoint) {
        let distance = hypot(tip.x - tail.x, tip.y - tail.y)
        let length: CGFloat = min(max(CGFloat(width) * 4, 16), distance)
        let ux = (tip.x - tail.x) / max(distance, 1)
        let uy = (tip.y - tail.y) / max(distance, 1)
        let wing: CGFloat = 0.45
        func back(_ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - (ux + side * wing * -uy) * length, y: tip.y - (uy + side * wing * ux) * length)
        }
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: back(1))
        path.line(to: back(-1))
        path.close()
        return (path, CGPoint(x: tip.x - ux * length * 0.8, y: tip.y - uy * length * 0.8))
    }
}
