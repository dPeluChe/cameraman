//
//  OverlayRenderer.swift
//  EngineKit
//
//  Overlay shape rendering for MaskedVideoCompositor.
//  Renders arrows, rectangles, lines, and text overlays into CIImage layers.
//

import CoreImage
import CoreGraphics
import CoreText

extension MaskedVideoCompositor {

    /// Render overlay shapes to a transparent CIImage layer (cacheable)
    func renderOverlayLayer(_ overlays: [(OverlayConfig, Double)], currentTime: TimeInterval, renderSize: CGSize) -> CIImage {
        let clearImage = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        guard let ctx = createBGRAContext(size: renderSize) else { return clearImage }

        ctx.clear(CGRect(origin: .zero, size: renderSize))

        for (overlay, opacity) in overlays {
            renderOverlay(overlay, opacity: opacity, currentTime: currentTime, in: ctx, renderSize: renderSize)
        }

        guard let cgImage = ctx.makeImage() else { return clearImage }
        return CIImage(cgImage: cgImage)
    }

    private func renderOverlay(_ overlay: OverlayConfig, opacity: Double, currentTime: TimeInterval, in ctx: CGContext, renderSize: CGSize) {
        guard opacity > 0.01 else { return }
        let overlayType = Project.Overlay.OverlayType(rawValue: overlay.type) ?? .rect
        let baseSize = OverlayBaseSize.size(for: overlayType, canvasSize: renderSize)

        let scaledW = baseSize.width * overlay.scale
        let scaledH = baseSize.height * overlay.scale
        let cx = overlay.x * renderSize.width
        let cy = (1.0 - overlay.y) * renderSize.height

        ctx.saveGState()
        ctx.setAlpha(CGFloat(opacity))
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: overlay.rotation * .pi / 180.0)

        if overlay.shadow {
            ctx.setShadow(offset: CGSize(width: 4, height: 4), blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        }

        let color = cgColor(from: overlay.stroke)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(overlay.strokeWidth)
        let size = CGSize(width: scaledW, height: scaledH)

        switch overlayType {
        case .arrow:
            renderArrowShape(in: ctx, size: size, color: color, strokeWidth: overlay.strokeWidth)
        case .rect:
            renderRectShape(in: ctx, size: size, color: color, strokeWidth: overlay.strokeWidth, bgColor: overlay.bgColor)
        case .line:
            renderLineShape(in: ctx, size: size, color: color, strokeWidth: overlay.strokeWidth)
        case .text:
            renderTextShape(in: ctx, size: size, text: overlay.text ?? "Text", fontSize: overlay.fontSize ?? 24, fontColor: overlay.fontColor ?? "#FFFFFF", bgColor: overlay.bgColor)
        case .image:
            if let path = overlay.imagePath {
                let elapsed = currentTime - overlay.start
                renderImageOverlay(path: path, elapsed: elapsed, opacityMultiplier: overlay.imageOpacity, in: ctx, size: size)
            }
        }

        ctx.restoreGState()
    }

    private func renderArrowShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double) {
        let path = CGMutablePath()
        let shaftW = size.width * 0.7
        let shaftH = size.height * 0.2
        let headH = size.height * 0.8

        path.move(to: CGPoint(x: -size.width / 2, y: -shaftH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: -shaftH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: -headH / 2))
        path.addLine(to: CGPoint(x: size.width / 2, y: 0))
        path.addLine(to: CGPoint(x: shaftW / 2, y: headH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: shaftH / 2))
        path.addLine(to: CGPoint(x: -size.width / 2, y: shaftH / 2))
        path.closeSubpath()

        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func renderRectShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double, bgColor: String?) {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let radius: CGFloat = 10

        if let bg = bgColor {
            ctx.setFillColor(cgColor(from: bg))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }

        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    private func renderLineShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.move(to: CGPoint(x: -size.width / 2, y: 0))
        ctx.addLine(to: CGPoint(x: size.width / 2, y: 0))
        ctx.strokePath()
    }

    private func renderTextShape(in ctx: CGContext, size: CGSize, text: String, fontSize: Double, fontColor: String, bgColor: String?) {
        // Draw directly into ctx (bottom-left origin, like the arrow/rect shapes
        // that render correctly). The previous offscreen + scaleY:-1 text matrix
        // assumed a flipped context, so the text landed off-canvas — the box
        // showed but the caption text never did.
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let color = cgColor(from: fontColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Background hugs the text (with padding) rather than the full overlay
        // box, so the caption pill matches the line width.
        if let bg = bgColor {
            let padX = fontSize * 0.45
            let padY = fontSize * 0.28
            let boxW = bounds.width + padX * 2
            let boxH = bounds.height + padY * 2
            let boxRect = CGRect(x: -boxW / 2, y: -boxH / 2, width: boxW, height: boxH)
            ctx.setFillColor(cgColor(from: bg))
            ctx.addPath(CGPath(roundedRect: boxRect, cornerWidth: padY, cornerHeight: padY, transform: nil))
            ctx.fillPath()
        }

        ctx.saveGState()
        ctx.textMatrix = .identity
        // Center the line on the overlay's origin (ctx is already translated there).
        ctx.textPosition = CGPoint(
            x: -bounds.width / 2 - bounds.minX,
            y: -bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
