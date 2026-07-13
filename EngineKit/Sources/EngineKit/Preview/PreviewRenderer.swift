//
//  PreviewRenderer.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import CoreGraphics
import CoreText
import AppKit

extension PreviewEngine {
    /// Render overlays on a frame
    /// - Parameters:
    ///   - image: Base frame image
    ///   - time: Current timeline time
    ///   - project: Project with overlay configuration
    /// - Returns: CGImage with overlays rendered
    /// - Throws: PreviewError if rendering fails
    func renderOverlays(on image: CGImage, at time: TimeInterval, project: Project) async throws -> CGImage {
        let canvasWidth = project.canvas.format.w
        let canvasHeight = project.canvas.format.h

        // Get active overlays at current time
        let activeOverlays = project.overlays.filter { overlay in
            time >= overlay.start && time <= overlay.end
        }

        // Get active image overlays at current time
        let activeImageItems = project.mediaItems.filter { item in
            item.type == .image && time >= item.timelineIn && time <= item.timelineOut
        }

        // Get active caption at current time
        let activeCaption = await captionsManager.getCaption(at: time)

        // If no active overlays, captions, or image items, return original image (or zoomed image)
        if activeOverlays.isEmpty && activeCaption == nil && activeImageItems.isEmpty {
            // Apply zoom if enabled
            if zoomEnabled, let zoomPlan = zoomPlan {
                return try await applyZoom(to: image, at: time, zoomPlan: zoomPlan, canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
            }
            return image
        }

        // Create bitmap context for rendering
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: image.bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            throw PreviewError.playbackFailed("Failed to create graphics context")
        }

        // Apply zoom transformation if enabled
        let zoomApplied = zoomEnabled && zoomPlan != nil
        if zoomApplied, let zoomPlan = zoomPlan {
            try await applyZoomTransform(to: context, at: time, zoomPlan: zoomPlan, imageSize: CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height)), canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        }

        // Draw original image
        let imageRect = CoreFoundation.CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        context.draw(image, in: imageRect)

        // Restore context after zoom transform (so overlays are not zoomed)
        if zoomApplied {
            context.restoreGState()
        }

        // Render each overlay
        for overlay in activeOverlays {
            try renderOverlay(overlay, in: context, imageSize: CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height)), canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        }

        // Render caption if active
        if let caption = activeCaption {
            try await renderCaption(caption, in: context, imageSize: CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height)), canvasSize: CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        }

        // Render image overlays if active
        if !activeImageItems.isEmpty, let renderer = imageOverlayRenderer {
            let canvasSizeCG = CoreFoundation.CGSize(width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))
            let imageSizeCG = CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            for item in activeImageItems {
                try renderer.render(mediaItem: item, in: context, canvasSize: canvasSizeCG, imageSize: imageSizeCG)
            }
        }

        // Extract final image
        guard let finalImage = context.makeImage() else {
            throw PreviewError.playbackFailed("Failed to create final image with overlays")
        }

        return finalImage
    }

    /// Render a single overlay on the graphics context
    /// - Parameters:
    ///   - overlay: Overlay to render
    ///   - context: Graphics context
    ///   - imageSize: Size of the image being rendered
    ///   - canvasSize: Canvas format size
    /// - Throws: PreviewError if rendering fails
    private func renderOverlay(
        _ overlay: Project.Overlay,
        in context: CGContext,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) throws {
        // Calculate actual position based on canvas format
        let center = OverlayCanvasGeometry.renderPoint(
            x: overlay.transform.x,
            y: overlay.transform.y,
            in: canvasSize
        )

        // Calculate scale based on image size vs canvas size
        let scaleX = imageSize.width / CGFloat(canvasSize.width)
        let scaleY = imageSize.height / CGFloat(canvasSize.height)

        // Get base size for this overlay type (relative to canvas)
        let baseSize = OverlayBaseSize.size(for: overlay.type, canvasSize: canvasSize)

        // Calculate the scale factor to apply so baseSize maps to the shape's expected unit size
        let shapeUnitSize: CGFloat = 100 // All shapes draw within ~100px unit
        let sizeScaleX = (baseSize.width * scaleX) / shapeUnitSize
        let sizeScaleY = (baseSize.height * scaleY) / shapeUnitSize

        // Save context state
        context.saveGState()

        // Apply transformations: position, size scale, user scale, rotation
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: sizeScaleX * overlay.transform.scale, y: sizeScaleY * overlay.transform.scale)
        context.rotate(by: overlay.transform.rotation * .pi / 180.0)

        // Apply shadow if enabled
        if overlay.style.shadow {
            context.setShadow(offset: CoreFoundation.CGSize(width: 4, height: 4), blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        }

        // Render based on overlay type
        switch overlay.type {
        case .arrow:
            try renderArrow(overlay, in: context)

        case .rect:
            try renderRectangle(overlay, in: context)

        case .line:
            try renderLine(overlay, in: context)

        case .text:
            try renderText(overlay, in: context)

        case .image:
            // Image overlays are rendered by MaskedVideoCompositor; the
            // SwiftUI-side PreviewRenderer doesn't draw them (it's used for
            // proxy thumbnails / static frames where image overlays are not
            // a primary concern).
            break
        }

        // Restore context state
        context.restoreGState()
    }

    /// Render a caption on the graphics context
    /// - Parameters:
    ///   - caption: Caption entry to render
    ///   - context: Graphics context
    ///   - imageSize: Size of the image being rendered
    ///   - canvasSize: Canvas format size
    /// - Throws: PreviewError if rendering fails
    private func renderCaption(
        _ caption: CaptionsManager.CaptionEntry,
        in context: CGContext,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) async throws {
        let style = await captionsManager.getStyle()

        // Calculate font size based on image height
        let fontSize = style.fontSize * CGFloat(imageSize.height)

        // Create font
        let font = CTFontCreateWithName(style.fontFamily as CFString, fontSize, nil)

        // Create paragraph style for alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = style.horizontalAlignment < 0.33 ? .left :
                                   style.horizontalAlignment > 0.66 ? .right : .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        // Create text attributes
        let textColor = parseColor(style.textColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Create attributed string
        let attributedString = NSAttributedString(string: caption.text, attributes: attributes)

        // Measure text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let maxWidth = style.maxLineWidth * CGFloat(imageSize.width)
        let textBounds = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CoreFoundation.CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            nil
        )

        // Calculate caption position (bottom of screen by default)
        let padding: CGFloat = 20
        let x = style.horizontalAlignment * CGFloat(imageSize.width)
        let y = (1.0 - style.verticalPosition) * CGFloat(imageSize.height) - textBounds.height - padding

        // Draw background if opacity > 0
        if style.backgroundOpacity > 0 {
            let bgColor = parseColor(style.backgroundColor)
            let bgPadding: CGFloat = 12

            // Calculate background rect based on alignment
            var bgX: CGFloat
            switch paragraphStyle.alignment {
            case .left:
                bgX = x - bgPadding
            case .right:
                bgX = x - textBounds.width - bgPadding
            default:
                bgX = x - textBounds.width / 2 - bgPadding
            }

            let bgRect = CoreFoundation.CGRect(
                x: bgX,
                y: y - bgPadding,
                width: textBounds.width + bgPadding * 2,
                height: textBounds.height + bgPadding * 2
            )

            // Create background color with opacity
            let bgComponents = bgColor.components ?? [0, 0, 0, 1]
            let bgColorWithAlpha = CGColor(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: bgComponents
            )?.copy(alpha: style.backgroundOpacity) ?? bgColor

            context.setFillColor(bgColorWithAlpha)
            context.fill([bgRect])
        }

        // Draw shadow if enabled
        if style.shadow {
            context.setShadow(offset: CoreFoundation.CGSize(width: 2, height: 2), blur: 4, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8))
        } else {
            context.setShadow(offset: .zero, blur: 0, color: nil)
        }

        // Adjust x position based on alignment
        let adjustedRect: CoreFoundation.CGRect
        switch paragraphStyle.alignment {
        case .left:
            adjustedRect = CoreFoundation.CGRect(x: x, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        case .right:
            adjustedRect = CoreFoundation.CGRect(x: x - textBounds.width, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        default:
            adjustedRect = CoreFoundation.CGRect(x: x - textBounds.width / 2, y: y, width: min(textBounds.width, maxWidth), height: textBounds.height)
        }

        let textPath = CGPath(rect: adjustedRect, transform: nil)
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)

        CTFrameDraw(textFrame, context)
    }

    /// Load captions from file paths
    /// - Parameters:
    ///   - srtPath: Relative path to SRT file
    ///   - vttPath: Relative path to VTT file
    ///   - projectDirectory: Project directory path
    func loadCaptions(srtPath: String, vttPath: String, projectDirectory: String) async {
        // Prefer VTT if available, otherwise use SRT
        let vttFullPath = (projectDirectory as NSString).appendingPathComponent(vttPath)
        let srtFullPath = (projectDirectory as NSString).appendingPathComponent(srtPath)

        let captionPath = FileManager.default.fileExists(atPath: vttFullPath) ? vttFullPath : srtFullPath

        do {
            try await captionsManager.loadCaptions(from: captionPath)
        } catch {
            // If captions fail to load, just continue without them
            // This is not a fatal error for preview
            logger.warning("Failed to load captions: \(error.localizedDescription)")
        }
    }

    /// Get active overlays at a specific time
    /// - Parameter time: Timeline time in seconds
    /// - Returns: Array of active overlays
    public func getActiveOverlays(at time: TimeInterval) -> [Project.Overlay] {
        guard let project = project else {
            return []
        }

        return project.overlays.filter { overlay in
            time >= overlay.start && time <= overlay.end
        }
    }

    /// Returns zoom level and focus coordinates in image space, or nil if zoom is inactive.
    private func zoomState(
        at time: TimeInterval,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        imageSize: CoreFoundation.CGSize
    ) -> (level: Double, focusX: CGFloat, focusY: CGFloat)? {
        let zoomLevel = zoomPlan.zoomLevel(at: time)
        guard zoomLevel > 1.01 else { return nil }
        let focusPoint = zoomPlan.focusPoint(at: time)
        // focusPoint is in canvas-normalised space; multiplying by imageSize maps to pixel space
        // (canvasSize cancels out when converting: focusPoint.x * canvasW * (imageW / canvasW) = focusPoint.x * imageW)
        return (zoomLevel, focusPoint.x * imageSize.width, focusPoint.y * imageSize.height)
    }

    private func applyZoomTransform(
        to context: CGContext,
        at time: TimeInterval,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) async throws {
        guard let state = zoomState(at: time, zoomPlan: zoomPlan, imageSize: imageSize) else { return }
        context.saveGState()
        context.translateBy(x: state.focusX, y: state.focusY)
        context.scaleBy(x: CGFloat(state.level), y: CGFloat(state.level))
        context.translateBy(x: -state.focusX, y: -state.focusY)
    }

    public func applyZoom(
        to image: CGImage,
        at time: TimeInterval,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        canvasSize: CoreFoundation.CGSize
    ) async throws -> CGImage {
        let imageSize = CoreFoundation.CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        guard let state = zoomState(at: time, zoomPlan: zoomPlan, imageSize: imageSize) else { return image }

        let newWidth = Int(Double(image.width) * state.level)
        let newHeight = Int(Double(image.height) * state.level)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            throw PreviewError.playbackFailed("Failed to create graphics context for zoom")
        }

        let cropWidth = CGFloat(image.width) / CGFloat(state.level)
        let cropHeight = CGFloat(image.height) / CGFloat(state.level)
        let cropX = max(0, min(state.focusX - cropWidth / 2, CGFloat(image.width) - cropWidth))
        let cropY = max(0, min(state.focusY - cropHeight / 2, CGFloat(image.height) - cropHeight))

        let cropRect = CoreFoundation.CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        context.clip(to: [cropRect])
        context.draw(image, in: CoreFoundation.CGRect(x: cropRect.origin.x, y: cropRect.origin.y, width: CGFloat(image.width), height: CGFloat(image.height)))

        guard let zoomedImage = context.makeImage() else {
            throw PreviewError.playbackFailed("Failed to create zoomed image")
        }
        return zoomedImage
    }
}
