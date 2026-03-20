//
//  PreviewRendererShapes.swift
//  EngineKit
//
//  Extracted from PreviewRenderer.swift — individual shape render methods
//

import Foundation
import CoreGraphics
import CoreText
import AppKit

extension PreviewEngine {
    /// Render an arrow overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    func renderArrow(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Arrow shape: pointing right by default
        // Arrow consists of a line and a triangular head
        let arrowLength: CGFloat = 100
        let headLength: CGFloat = 30
        let headWidth: CGFloat = 20

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw arrow shaft
        context.move(to: CGPoint(x: -arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: 0))

        // Draw arrow head
        context.move(to: CGPoint(x: arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: -headWidth / 2))
        context.move(to: CGPoint(x: arrowLength / 2, y: 0))
        context.addLine(to: CGPoint(x: arrowLength / 2 - headLength, y: headWidth / 2))

        context.strokePath()
    }

    /// Render a rectangle overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    func renderRectangle(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Default rectangle size
        let rectWidth: CGFloat = 200
        let rectHeight: CGFloat = 150
        let cornerRadius: CGFloat = 10

        let rect = CoreFoundation.CGRect(
            x: -rectWidth / 2,
            y: -rectHeight / 2,
            width: rectWidth,
            height: rectHeight
        )

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)

        // Create rounded rectangle path
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
    }

    /// Render a line overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    func renderLine(_ overlay: Project.Overlay, in context: CGContext) throws {
        let strokeColor = parseColor(overlay.style.stroke)
        let strokeWidth = CGFloat(overlay.style.strokeWidth)

        // Default line dimensions (horizontal line)
        let lineLength: CGFloat = 200

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        // Draw line centered at origin
        context.move(to: CGPoint(x: -lineLength / 2, y: 0))
        context.addLine(to: CGPoint(x: lineLength / 2, y: 0))

        context.strokePath()
    }

    /// Render a text overlay
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    /// - Throws: PreviewError if rendering fails
    func renderText(_ overlay: Project.Overlay, in context: CGContext) throws {
        guard let text = overlay.style.text else {
            throw PreviewError.playbackFailed("Text overlay has no text content")
        }

        let textColor = parseColor(overlay.style.color ?? "#FFFFFF")
        let fontSize = overlay.style.size ?? 24
        let fontName = overlay.style.font ?? "Helvetica"

        // Set text attributes
        context.setTextDrawingMode(.fill)
        context.setFillColor(textColor)

        // Create font
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)

        // Create text attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        // Create attributed string
        let attributedString = NSAttributedString(string: text, attributes: attributes)

        // Measure text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textBounds = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CoreFoundation.CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            nil
        )

        // Draw background if specified
        if let bgColorHex = overlay.style.bg {
            let bgColor = parseColor(bgColorHex)
            let bgPadding: CGFloat = 8
            let bgRect = CoreFoundation.CGRect(
                x: -textBounds.width / 2 - bgPadding,
                y: -textBounds.height / 2 - bgPadding,
                width: textBounds.width + bgPadding * 2,
                height: textBounds.height + bgPadding * 2
            )

            context.setFillColor(bgColor)
            context.fill([bgRect])
        }

        // Draw text centered at origin
        let textRect = CoreFoundation.CGRect(
            x: -textBounds.width / 2,
            y: -textBounds.height / 2,
            width: textBounds.width,
            height: textBounds.height
        )

        let textPath = CGPath(rect: textRect, transform: nil)
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)

        CTFrameDraw(textFrame, context)
    }

    /// Parse a hex color string to CGColor
    /// - Parameter hex: Hex color string (e.g., "#FFFFFF" or "#FFFFFF80" for alpha)
    /// - Returns: CGColor
    func parseColor(_ hex: String) -> CGColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgba: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgba)

        let r, g, b, a: CGFloat
        let length = hexSanitized.count

        if length == 6 {
            // RGB without alpha
            r = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgba & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            // RGBA with alpha
            r = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgba & 0x000000FF) / 255.0
        } else {
            // Default to white if invalid
            r = 1.0
            g = 1.0
            b = 1.0
            a = 1.0
        }

        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
