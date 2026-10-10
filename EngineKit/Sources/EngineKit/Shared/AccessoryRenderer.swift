//
//  AccessoryRenderer.swift
//  EngineKit
//
//  Draws the built-in accessories (vector art, no assets) onto a camera frame at the face anchors.
//  Each piece is drawn once at a canonical size and cached; per frame it is only moved, scaled and
//  rotated, so the cost is a few CIImage transforms.
//

import Foundation
import AppKit
import CoreImage
import CoreGraphics

enum AccessoryRenderer {
    /// Returns `image` with the accessories drawn over it, cropped to the original frame. `anchors` is
    /// nil when no face was found: face-anchored pieces are skipped, frame-pinned ones still draw.
    /// `images` maps each custom accessory to its file on disk.
    static func apply(_ accessories: Project.CameraAccessories, anchors: FaceAnchors?, images: [UUID: URL] = [:], to image: CIImage) -> CIImage {
        var result = image
        if let anchors {
            for kind in accessories.kinds {
                result = placed(kind, anchors: anchors, scale: accessories.scale).composited(over: result)
            }
        }
        for item in accessories.custom {
            guard let url = images[item.id], let drawn = custom(item, imageURL: url, anchors: anchors, frame: image.extent) else { continue }
            result = drawn.composited(over: result)
        }
        return result.cropped(to: image.extent)
    }

    // MARK: - Custom images

    /// Where an image sits: the point on the frame it is pinned to and which point of the image goes there
    /// (0...1 in each axis, origin bottom-left).
    private static func custom(_ item: Project.CustomAccessory, imageURL: URL, anchors: FaceAnchors?, frame: CGRect) -> CIImage? {
        let width: CGFloat
        var point: CGPoint
        let pivot: CGPoint
        var rotation: CGFloat = 0
        switch item.anchor {
        case .headTop, .eyes:
            guard let anchors else { return nil }
            width = anchors.faceBox.width * CGFloat(item.size)
            rotation = anchors.roll
            if item.anchor == .eyes {
                point = anchors.eyeMidpoint
                pivot = CGPoint(x: 0.5, y: 0.5)
            } else {
                let up = CGPoint(x: -sin(anchors.roll), y: cos(anchors.roll))
                let toTop = max(0, anchors.faceBox.maxY - anchors.eyeMidpoint.y)
                point = CGPoint(x: anchors.eyeMidpoint.x + up.x * toTop * 0.95, y: anchors.eyeMidpoint.y + up.y * toTop * 0.95)
                pivot = CGPoint(x: 0.5, y: 0)
            }
        default:
            width = frame.width * CGFloat(item.size)
            let margin = 0.03 * min(frame.width, frame.height)
            let (px, py): (CGFloat, CGFloat)
            switch item.anchor {
            case .topLeft: (px, py) = (0, 1)
            case .topCenter: (px, py) = (0.5, 1)
            case .topRight: (px, py) = (1, 1)
            case .center: (px, py) = (0.5, 0.5)
            case .bottomLeft: (px, py) = (0, 0)
            case .bottomCenter: (px, py) = (0.5, 0)
            default: (px, py) = (1, 0)
            }
            pivot = CGPoint(x: px, y: py)
            // Inset from the edge the piece hangs on (+ at 0, - at 1, none when centered).
            point = CGPoint(x: frame.minX + frame.width * px + margin * (1 - 2 * px),
                            y: frame.minY + frame.height * py + margin * (1 - 2 * py))
        }
        point.x += CGFloat(item.offsetX) * frame.width
        point.y += CGFloat(item.offsetY) * frame.height

        guard width > 1, let art = rasterized(imageURL, width: width) else { return nil }
        let scale = width / art.extent.width
        var transform = CGAffineTransform(translationX: -pivot.x * art.extent.width, y: -pivot.y * art.extent.height)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
        var drawn = art.transformed(by: transform)
        if item.opacity < 0.999 {
            drawn = drawn.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, item.opacity)))])
        }
        return drawn
    }

    private static let rasterLock = NSLock()
    nonisolated(unsafe) private static var rasterCache: [(key: String, image: CIImage)] = []
    private static let rasterCacheLimit = 12

    /// The file drawn at about `width` pixels (bucketed, so a size slider does not rasterize per pixel).
    /// SVGs are drawn into the bitmap at that size, so they stay sharp.
    private static func rasterized(_ url: URL, width: CGFloat) -> CIImage? {
        let bucket = min(2048, max(64, Int((width / 64).rounded(.up)) * 64))
        let key = "\(url.path)|\(bucket)"
        rasterLock.lock()
        defer { rasterLock.unlock() }
        if let hit = rasterCache.first(where: { $0.key == key }) { return hit.image }

        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else { return nil }
        let height = max(1, Int((CGFloat(bucket) * source.size.height / source.size.width).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: bucket, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: CGRect(x: 0, y: 0, width: bucket, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { return nil }

        let image = CIImage(cgImage: cg)
        if rasterCache.count >= rasterCacheLimit { rasterCache.removeFirst() }
        rasterCache.append((key, image))
        return image
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

    /// Drawn on first use; a `static let` is initialized once and thread-safe.
    private static let arts: [Project.CameraAccessories.Kind: CIImage] = Dictionary(
        uniqueKeysWithValues: Project.CameraAccessories.Kind.allCases.map { ($0, draw($0)) }
    )

    private static func art(for kind: Project.CameraAccessories.Kind) -> CIImage {
        arts[kind] ?? CIImage.empty()
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
