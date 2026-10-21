//
//  LiveAnnotationRenderer.swift
//  App
//
//  Draws live annotations into the current graphics context (top-left origin).
//

import AppKit
import SwiftUI
import EngineKit

/// Draws one annotation. Shared by committed shapes and the draft being dragged.
enum LiveAnnotationRenderer {
    static func color(_ hex: String) -> NSColor { NSColor(Color(hex: hex)) }

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
            NSBezierPath(roundedRect: rect(pts), xRadius: 4, yRadius: 4).stroked(width: annotation.lineWidth)
        case .ellipse:
            NSBezierPath(ovalIn: rect(pts)).stroked(width: annotation.lineWidth)
        case .blur:
            // The live blur is a visual-effect subview; only the draft outline is drawn here.
            break
        case .text:
            let font = NSFont.systemFont(ofSize: textSize(for: annotation.lineWidth), weight: .bold)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            (annotation.text ?? "").draw(at: first, withAttributes: [.font: font, .foregroundColor: color, .shadow: shadow])
        }
    }

    static func textSize(for lineWidth: Double) -> CGFloat { CGFloat(14 + lineWidth * 5) }

    static func rect(_ pts: [CGPoint]) -> CGRect {
        guard let a = pts.first, let b = pts.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
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

private extension NSBezierPath {
    func stroked(width: CGFloat) {
        lineWidth = width
        stroke()
    }
}
