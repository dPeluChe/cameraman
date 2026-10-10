//
//  AccessoryRenderer.swift
//  EngineKit
//
//  Draws the built-in accessories (vector art, no assets) onto a camera frame at the face anchors.
//  Each piece is drawn once at a canonical size and cached; per frame it is only moved, scaled and
//  rotated, so the cost is a few CIImage transforms.
//

import Foundation
import CoreImage
import CoreGraphics

enum AccessoryRenderer {
    /// Returns `image` with the accessories drawn over it, cropped to the original frame.
    static func apply(_ accessories: Project.CameraAccessories, anchors: FaceAnchors, to image: CIImage) -> CIImage {
        var result = image
        for kind in accessories.kinds {
            result = placed(kind, anchors: anchors, scale: accessories.scale).composited(over: result)
        }
        return result.cropped(to: image.extent)
    }

    // MARK: - Placement

    private struct Placement {
        /// Point of the art that sits on the face anchor.
        let artAnchor: CGPoint
        /// Width of the part of the art that should span `faceWidth` on the face.
        let artWidth: CGFloat
        let faceAnchor: CGPoint
        let faceWidth: CGFloat
    }

    private static func placement(for kind: Project.CameraAccessories.Kind, anchors: FaceAnchors) -> Placement {
        let eyes = anchors.eyeMidpoint
        let up = CGPoint(x: -sin(anchors.roll), y: cos(anchors.roll))
        let toTop = max(0, anchors.faceBox.maxY - eyes.y)
        switch kind {
        case .glasses, .sunglasses:
            // The art has its eye centers 300 px apart.
            return Placement(artAnchor: CGPoint(x: 300, y: 120), artWidth: 300, faceAnchor: eyes, faceWidth: anchors.eyeDistance)
        case .partyHat:
            return Placement(artAnchor: CGPoint(x: 200, y: 40), artWidth: 340,
                             faceAnchor: CGPoint(x: eyes.x + up.x * toTop * 0.95, y: eyes.y + up.y * toTop * 0.95),
                             faceWidth: anchors.faceBox.width * 0.9)
        case .crown:
            return Placement(artAnchor: CGPoint(x: 230, y: 20), artWidth: 420,
                             faceAnchor: CGPoint(x: eyes.x + up.x * toTop * 0.88, y: eyes.y + up.y * toTop * 0.88),
                             faceWidth: anchors.faceBox.width * 1.0)
        }
    }

    private static func placed(_ kind: Project.CameraAccessories.Kind, anchors: FaceAnchors, scale: Double) -> CIImage {
        let p = placement(for: kind, anchors: anchors)
        let k = p.faceWidth * CGFloat(scale) / p.artWidth
        let transform = CGAffineTransform(translationX: -p.artAnchor.x, y: -p.artAnchor.y)
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(rotationAngle: anchors.roll))
            .concatenating(CGAffineTransform(translationX: p.faceAnchor.x, y: p.faceAnchor.y))
        return art(for: kind).transformed(by: transform)
    }

    // MARK: - Art

    private static let artLock = NSLock()
    nonisolated(unsafe) private static var artCache: [Project.CameraAccessories.Kind: CIImage] = [:]

    private static func art(for kind: Project.CameraAccessories.Kind) -> CIImage {
        artLock.lock()
        defer { artLock.unlock() }
        if let cached = artCache[kind] { return cached }
        let image = draw(kind)
        artCache[kind] = image
        return image
    }

    private static func draw(_ kind: Project.CameraAccessories.Kind) -> CIImage {
        let size: CGSize
        switch kind {
        case .glasses, .sunglasses: size = CGSize(width: 600, height: 240)
        case .partyHat: size = CGSize(width: 400, height: 520)
        case .crown: size = CGSize(width: 460, height: 300)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return CIImage.empty() }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        switch kind {
        case .glasses: drawGlasses(ctx, filled: false)
        case .sunglasses: drawGlasses(ctx, filled: true)
        case .partyHat: drawPartyHat(ctx)
        case .crown: drawCrown(ctx)
        }
        guard let cg = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: cg)
    }

    private static func drawGlasses(_ ctx: CGContext, filled: Bool) {
        let centers = [CGPoint(x: 150, y: 120), CGPoint(x: 450, y: 120)]
        let frameColor = CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        // Temples and bridge.
        ctx.setStrokeColor(frameColor)
        ctx.setLineWidth(filled ? 16 : 14)
        ctx.move(to: CGPoint(x: 0, y: 150)); ctx.addLine(to: CGPoint(x: 52, y: 135))
        ctx.move(to: CGPoint(x: 600, y: 150)); ctx.addLine(to: CGPoint(x: 548, y: 135))
        ctx.move(to: CGPoint(x: 252, y: 132)); ctx.addQuadCurve(to: CGPoint(x: 348, y: 132), control: CGPoint(x: 300, y: 168))
        ctx.strokePath()
        for center in centers {
            let rect = CGRect(x: center.x - 102, y: center.y - (filled ? 78 : 96), width: 204, height: filled ? 156 : 192)
            if filled {
                ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.9))
                ctx.fillEllipse(in: rect)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
                ctx.fillEllipse(in: CGRect(x: rect.minX + 28, y: rect.midY + 6, width: 72, height: 30))
            }
            ctx.setStrokeColor(frameColor)
            ctx.setLineWidth(filled ? 16 : 14)
            ctx.strokeEllipse(in: rect)
        }
    }

    private static func drawPartyHat(_ ctx: CGContext) {
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: 30, y: 40)); triangle.addLine(to: CGPoint(x: 370, y: 40)); triangle.addLine(to: CGPoint(x: 200, y: 450))
        triangle.closeSubpath()
        ctx.saveGState()
        ctx.addPath(triangle); ctx.clip()
        ctx.setFillColor(CGColor(red: 0.93, green: 0.25, blue: 0.45, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 520))
        // Diagonal stripes.
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        for i in stride(from: -2, through: 5, by: 2) {
            let y = CGFloat(i) * 60 + 60
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: 400, y: y + 150))
            ctx.addLine(to: CGPoint(x: 400, y: y + 190)); ctx.addLine(to: CGPoint(x: 0, y: y + 40)); ctx.closePath(); ctx.fillPath()
        }
        ctx.restoreGState()
        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 160, y: 430, width: 80, height: 80))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 30, y: 28, width: 340, height: 26))
    }

    private static func drawCrown(_ ctx: CGContext) {
        let crown = CGMutablePath()
        crown.move(to: CGPoint(x: 20, y: 20)); crown.addLine(to: CGPoint(x: 20, y: 200))
        crown.addLine(to: CGPoint(x: 120, y: 120)); crown.addLine(to: CGPoint(x: 230, y: 270))
        crown.addLine(to: CGPoint(x: 340, y: 120)); crown.addLine(to: CGPoint(x: 440, y: 200))
        crown.addLine(to: CGPoint(x: 440, y: 20)); crown.closeSubpath()
        ctx.addPath(crown)
        ctx.setFillColor(CGColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1))
        ctx.fillPath()
        ctx.addPath(crown)
        ctx.setStrokeColor(CGColor(red: 0.72, green: 0.5, blue: 0.05, alpha: 1))
        ctx.setLineWidth(12)
        ctx.strokePath()
        let jewels: [(CGPoint, CGColor)] = [
            (CGPoint(x: 230, y: 95), CGColor(red: 0.85, green: 0.1, blue: 0.2, alpha: 1)),
            (CGPoint(x: 110, y: 70), CGColor(red: 0.15, green: 0.5, blue: 0.9, alpha: 1)),
            (CGPoint(x: 350, y: 70), CGColor(red: 0.15, green: 0.7, blue: 0.4, alpha: 1))
        ]
        for (center, color) in jewels {
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48))
        }
    }
}
