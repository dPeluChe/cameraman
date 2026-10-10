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

    /// Where a custom image goes: the point it is pinned to, which point of the image sits there
    /// (0...1, origin bottom-left), its width on screen and its rotation.
    private struct CustomPlacement {
        let point: CGPoint
        let pivot: CGPoint
        let width: CGFloat
        let rotation: CGFloat
    }

    private static func placement(of item: Project.CustomAccessory, anchors: FaceAnchors?, frame: CGRect) -> CustomPlacement? {
        if let pivot = item.anchor.framePivot {
            // Inset from the edge the piece hangs on (+ at 0, - at 1, none when centered).
            let margin = 0.03 * min(frame.width, frame.height)
            return CustomPlacement(
                point: CGPoint(x: frame.minX + frame.width * pivot.x + margin * (1 - 2 * pivot.x),
                               y: frame.minY + frame.height * pivot.y + margin * (1 - 2 * pivot.y)),
                pivot: pivot, width: frame.width * CGFloat(item.size), rotation: 0)
        }
        guard let anchors else { return nil }
        let width = anchors.faceBox.width * CGFloat(item.size)
        if item.anchor == .eyes {
            return CustomPlacement(point: anchors.eyeMidpoint, pivot: CGPoint(x: 0.5, y: 0.5), width: width, rotation: anchors.roll)
        }
        return CustomPlacement(point: headTop(anchors, fraction: 0.95), pivot: CGPoint(x: 0.5, y: 0), width: width, rotation: anchors.roll)
    }

    /// A point `fraction` of the way from the eyes to the top of the head, along the head's tilt.
    private static func headTop(_ anchors: FaceAnchors, fraction: CGFloat) -> CGPoint {
        let up = CGPoint(x: -sin(anchors.roll), y: cos(anchors.roll))
        let toTop = max(0, anchors.faceBox.maxY - anchors.eyeMidpoint.y) * fraction
        return CGPoint(x: anchors.eyeMidpoint.x + up.x * toTop, y: anchors.eyeMidpoint.y + up.y * toTop)
    }

    private static func custom(_ item: Project.CustomAccessory, imageURL: URL, anchors: FaceAnchors?, frame: CGRect) -> CIImage? {
        guard var place = placement(of: item, anchors: anchors, frame: frame), place.width > 1,
              let art = rasterized(imageURL, width: place.width) else { return nil }
        place = CustomPlacement(
            point: CGPoint(x: place.point.x + CGFloat(item.offsetX) * frame.width, y: place.point.y + CGFloat(item.offsetY) * frame.height),
            pivot: place.pivot, width: place.width, rotation: place.rotation)

        let scale = place.width / art.extent.width
        let transform = CGAffineTransform(translationX: -place.pivot.x * art.extent.width, y: -place.pivot.y * art.extent.height)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: place.rotation))
            .concatenating(CGAffineTransform(translationX: place.point.x, y: place.point.y))
        var drawn = art.transformed(by: transform)
        if item.opacity < 0.999 {
            drawn = drawn.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, item.opacity)))])
        }
        return drawn
    }

    nonisolated(unsafe) private static var warned: Set<String> = []

    /// Without this a missing or unreadable file just draws nothing, with no hint why.
    private static func warnOnce(missing url: URL) {
        rasterLock.lock()
        let first = warned.insert(url.path).inserted
        rasterLock.unlock()
        if first { LogWarning(.preview, "[ACCESSORIES] cannot load \(url.path); nothing is drawn for it") }
    }

    private static let rasterLock = NSLock()
    nonisolated(unsafe) private static var rasterCache: [(key: String, image: CIImage)] = []
    private static let rasterCacheLimit = 12

    /// Pixel widths grow by 25% steps from 64, so a size slider re-rasterizes a few times, not per pixel.
    private static func bucket(for width: CGFloat) -> Int {
        let steps = ceil(log(max(width, 64) / 64) / log(1.25))
        return min(2048, Int((64 * pow(1.25, steps)).rounded()))
    }

    /// The file drawn at about `width` pixels. SVGs are drawn into the bitmap at that size, so they stay
    /// sharp. Decoding and drawing run outside the lock; two workers racing on a miss both draw, which is harmless.
    private static func rasterized(_ url: URL, width: CGFloat) -> CIImage? {
        let pixels = bucket(for: width)
        let key = "\(url.path)|\(pixels)"
        rasterLock.lock()
        if let index = rasterCache.firstIndex(where: { $0.key == key }) {
            let hit = rasterCache.remove(at: index)       // move to the end: most recently used
            rasterCache.append(hit)
            rasterLock.unlock()
            return hit.image
        }
        rasterLock.unlock()

        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else {
            warnOnce(missing: url)
            return nil
        }
        let height = max(1, Int((CGFloat(pixels) * source.size.height / source.size.width).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: CGRect(x: 0, y: 0, width: pixels, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { return nil }

        let image = CIImage(cgImage: cg)
        rasterLock.lock()
        if rasterCache.count >= rasterCacheLimit { rasterCache.removeFirst() }
        rasterCache.append((key, image))
        rasterLock.unlock()
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
        switch kind {
        case .glasses, .sunglasses:
            // The art has its eye centers 300 px apart.
            return Placement(artAnchor: CGPoint(x: 300, y: 120), artWidth: 300, faceAnchor: eyes, faceWidth: anchors.eyeDistance)
        case .partyHat:
            return Placement(artAnchor: CGPoint(x: 200, y: 40), artWidth: 340,
                             faceAnchor: headTop(anchors, fraction: 0.95),
                             faceWidth: anchors.faceBox.width * 0.9)
        case .crown:
            return Placement(artAnchor: CGPoint(x: 230, y: 20), artWidth: 420,
                             faceAnchor: headTop(anchors, fraction: 0.88),
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
