//
//  CursorRenderer.swift
//  EngineKit
//
//  Synthetic cursor + click-ripple rendering for MaskedVideoCompositor.
//  Positions come from `CursorPlan`, already normalized (0-1, bottom-left
//  origin) — the same convention CGContext/CIImage use natively here, so no
//  y-flip is needed (unlike `OverlayRenderer`, which flips top-left overlay
//  coordinates).
//

import AVFoundation
import CoreImage
import CoreGraphics

extension MaskedVideoCompositor {
    /// Draw the synthetic cursor dot and any active click ripples on top of
    /// `finalImage`. No-op when the instruction carries no plan/config or the
    /// feature is disabled.
    func compositeCursor(
        over finalImage: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        guard let config = instruction.cursorConfig, config.enabled,
              let plan = instruction.cursorPlan,
              let position = plan.position(at: request.compositionTime.seconds) else {
            return finalImage
        }

        guard let ctx = createBGRAContext(size: renderSize) else { return finalImage }
        ctx.clear(CGRect(origin: .zero, size: renderSize))

        if config.rippleEnabled {
            let ripples = plan.activeRipples(at: request.compositionTime.seconds)
            for (mark, age) in ripples {
                drawRipple(at: mark, age: age, in: ctx)
            }
        }

        drawCursorDot(at: position, scale: config.scale, color: config.color, in: ctx)

        guard let cgImage = ctx.makeImage() else { return finalImage }
        let cursorLayer = CIImage(cgImage: cgImage)
        return cursorLayer.composited(over: finalImage)
    }

    private func drawCursorDot(at position: (x: Double, y: Double), scale: Double, color: String, in ctx: CGContext) {
        let radius = 9.0 * max(0.25, scale)
        let cx = CGFloat(position.x) * ctx.width.cgFloat
        let cy = CGFloat(position.y) * ctx.height.cgFloat
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.5))
        ctx.setFillColor(cgColor(from: color))
        ctx.fillEllipse(in: rect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.85))
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    private func drawRipple(at mark: CursorClickMark, age: Double, in ctx: CGContext) {
        let minRadius = 10.0
        let maxRadius = 44.0
        let radius = minRadius + (maxRadius - minRadius) * age
        let alpha = 1.0 - age
        let cx = CGFloat(mark.x) * ctx.width.cgFloat
        let cy = CGFloat(mark.y) * ctx.height.cgFloat
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha * 0.9))
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }
}

private extension Int {
    var cgFloat: CGFloat { CGFloat(self) }
}
