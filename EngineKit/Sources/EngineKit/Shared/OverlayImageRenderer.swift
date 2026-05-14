//
//  OverlayImageRenderer.swift
//  EngineKit
//
//  Renders image-type overlays (PNG/JPG/SVG/GIF) into the compositor's
//  CGContext. Static formats draw a single rasterized frame; GIF picks the
//  frame matching the overlay's elapsed time (cumulative frame durations).
//  NSImage handles all four formats natively on macOS, so we lean on it
//  here instead of branching by extension. NSBitmapImageRep exposes GIF
//  frame metadata.
//

import AppKit
import CoreGraphics

extension MaskedVideoCompositor {

    /// Draw an image overlay into the compositor's transient context. The
    /// context is already translated to the overlay's center and rotated.
    /// `opacityMultiplier` stacks on top of the existing ctx.setAlpha (set by
    /// the caller for the fade animation).
    func renderImageOverlay(
        path: String,
        elapsed: TimeInterval,
        opacityMultiplier: Double,
        in ctx: CGContext,
        size: CGSize
    ) {
        guard let nsImage = loadImageAsset(path: path) else { return }

        let cgImage: CGImage?
        if let bitmapRep = nsImage.representations.first as? NSBitmapImageRep,
           let frameCount = bitmapRep.value(forProperty: .frameCount) as? Int,
           frameCount > 1 {
            // Animated GIF — pick the frame whose cumulative duration window
            // contains `elapsed`, wrapping if the elapsed exceeds the loop.
            cgImage = gifFrame(bitmapRep: bitmapRep, frameCount: frameCount, elapsed: elapsed, cacheKey: path)
        } else {
            // Static (PNG/JPG/SVG/single-frame GIF) — rasterize to the target
            // size. For SVG this is the rasterization step that vectorizes
            // crisply at any scale.
            cgImage = staticCGImage(from: nsImage, targetSize: size)
        }

        guard let cgImage else { return }

        // The compositor's outer transform centered the origin and rotated.
        // We draw centered on (0,0) with the requested size.
        let drawRect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

        // The caller already called ctx.setAlpha(animationOpacity); to stack
        // the per-overlay imageOpacity we wrap our draw in a transparency
        // layer with the multiplier alpha (CGContext doesn't expose the
        // current alpha to read+multiply directly).
        if abs(opacityMultiplier - 1.0) > 0.001 {
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setAlpha(CGFloat(max(0, min(1, opacityMultiplier))))
            ctx.draw(cgImage, in: drawRect)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        } else {
            ctx.draw(cgImage, in: drawRect)
        }
    }

    /// Load (or fetch cached) NSImage for the given asset path. Maintains a
    /// bounded LRU so a long-running session with many distinct images can't
    /// grow this cache unbounded.
    private func loadImageAsset(path: String) -> NSImage? {
        if let cached = cachedOverlayAssets[path] {
            // Bump LRU recency: move path to the end of the access order.
            cachedOverlayAssetOrder.removeAll { $0 == path }
            cachedOverlayAssetOrder.append(path)
            return cached
        }
        guard FileManager.default.fileExists(atPath: path),
              let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        cachedOverlayAssets[path] = image
        cachedOverlayAssetOrder.append(path)
        // Evict the oldest if we've grown past the cap.
        while cachedOverlayAssets.count > Self.maxCachedAssets,
              let oldest = cachedOverlayAssetOrder.first {
            cachedOverlayAssetOrder.removeFirst()
            cachedOverlayAssets.removeValue(forKey: oldest)
            cachedGifDurations.removeValue(forKey: oldest)
        }
        return image
    }

    /// Pick a GIF frame for the given elapsed time. Loops when elapsed >
    /// total loop duration. Caches per-frame durations per asset path —
    /// computing them requires `setProperty + read` for every frame which is
    /// slow on NSBitmapImageRep.
    private func gifFrame(
        bitmapRep: NSBitmapImageRep,
        frameCount: Int,
        elapsed: TimeInterval,
        cacheKey: String
    ) -> CGImage? {
        let durations: [TimeInterval]
        if let cached = cachedGifDurations[cacheKey] {
            durations = cached
        } else {
            var computed: [TimeInterval] = []
            computed.reserveCapacity(frameCount)
            for i in 0..<frameCount {
                bitmapRep.setProperty(.currentFrame, withValue: i)
                let d = (bitmapRep.value(forProperty: .currentFrameDuration) as? TimeInterval) ?? 0.1
                // Many GIFs encode 0/very-short delays; clamp to ~24fps min.
                computed.append(max(d, 0.04))
            }
            cachedGifDurations[cacheKey] = computed
            durations = computed
        }

        let total = durations.reduce(0, +)
        guard total > 0 else {
            bitmapRep.setProperty(.currentFrame, withValue: 0)
            return bitmapRep.cgImage
        }

        let looped = elapsed.truncatingRemainder(dividingBy: total)
        var acc: TimeInterval = 0
        var frameIndex = frameCount - 1
        for (i, d) in durations.enumerated() {
            acc += d
            if looped <= acc {
                frameIndex = i
                break
            }
        }
        bitmapRep.setProperty(.currentFrame, withValue: frameIndex)
        return bitmapRep.cgImage
    }

    /// Rasterize a static NSImage to a CGImage at the target size. For SVGs
    /// this is where the vector → bitmap conversion happens at the right
    /// resolution; for PNGs/JPGs it's a no-op pass-through.
    private func staticCGImage(from nsImage: NSImage, targetSize: CGSize) -> CGImage? {
        // Try the fast path first — most raster sources expose a CGImage.
        var proposedRect = CGRect(origin: .zero, size: targetSize)
        if let cg = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cg
        }
        // Fallback: render into a bitmap rep at the target size.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width.rounded()),
            pixelsHigh: Int(targetSize.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let gctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = gctx
            nsImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
