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
        let x = overlay.transform.x * CGFloat(canvasSize.width)
        let y = overlay.transform.y * CGFloat(canvasSize.height)

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
        context.translateBy(x: x, y: y)
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

        // Draw text
        let textRect = CoreFoundation.CGRect(x: x, y: y, width: textBounds.width, height: textBounds.height)

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

    /// Apply zoom transformation to a graphics context
    /// - Parameters:
    ///   - context: Graphics context to transform
    ///   - time: Current timeline time
    ///   - zoomPlan: Zoom plan with keyframes
    ///   - imageSize: Size of the image being rendered
    ///   - canvasSize: Canvas format size
    /// - Throws: PreviewError if transformation fails
    private func applyZoomTransform(
        to context: CGContext,
        at time: TimeInterval,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        imageSize: CoreFoundation.CGSize,
        canvasSize: CoreFoundation.CGSize
    ) async throws {
        // Get zoom level and focus point at current time
        let zoomLevel = zoomPlan.zoomLevel(at: time)
        let focusPoint = zoomPlan.focusPoint(at: time)

        // Only apply transform if zoom is active (> 1.0)
        guard zoomLevel > 1.01 else {
            return
        }

        // Save context state before transformation
        context.saveGState()

        // Calculate the scale factors
        let scaleX = imageSize.width / CGFloat(canvasSize.width)
        let scaleY = imageSize.height / CGFloat(canvasSize.height)

        // Calculate focus point in image coordinates
        let focusX = focusPoint.x * CGFloat(canvasSize.width) * scaleX
        let focusY = focusPoint.y * CGFloat(canvasSize.height) * scaleY

        // Apply zoom transformation
        // 1. Translate to focus point
        context.translateBy(x: focusX, y: focusY)

        // 2. Scale by zoom level
        context.scaleBy(x: CGFloat(zoomLevel), y: CGFloat(zoomLevel))

        // 3. Translate back from focus point
        context.translateBy(x: -focusX, y: -focusY)
    }

    /// Apply zoom to an image (for frames without overlays)
    /// - Parameters:
    ///   - image: Original image
    ///   - time: Current timeline time
    ///   - zoomPlan: Zoom plan with keyframes
    ///   - canvasSize: Canvas format size
    /// - Returns: Zoomed image, or original if zoom is not active
    /// - Throws: PreviewError if zoom application fails
    public func applyZoom(
        to image: CGImage,
        at time: TimeInterval,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        canvasSize: CoreFoundation.CGSize
    ) async throws -> CGImage {
        // Get zoom level and focus point at current time
        let zoomLevel = zoomPlan.zoomLevel(at: time)
        let focusPoint = zoomPlan.focusPoint(at: time)

        // Only apply zoom if zoom is active (> 1.01)
        guard zoomLevel > 1.01 else {
            return image
        }

        // Calculate new dimensions for zoomed image
        let newWidth = Int(Double(image.width) * zoomLevel)
        let newHeight = Int(Double(image.height) * zoomLevel)

        // Create bitmap context for zoomed image
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

        // Calculate the source rectangle to crop
        // We want to center on the focus point
        let scaleX = CGFloat(image.width) / CGFloat(canvasSize.width)
        let scaleY = CGFloat(image.height) / CGFloat(canvasSize.height)

        let focusX = focusPoint.x * CGFloat(canvasSize.width) * scaleX
        let focusY = focusPoint.y * CGFloat(canvasSize.height) * scaleY

        // Calculate the crop rectangle centered on focus point
        let cropWidth = CGFloat(image.width) / CGFloat(zoomLevel)
        let cropHeight = CGFloat(image.height) / CGFloat(zoomLevel)
        let cropX = max(0, min(focusX - cropWidth / 2, CGFloat(image.width) - cropWidth))
        let cropY = max(0, min(focusY - cropHeight / 2, CGFloat(image.height) - cropHeight))

        let cropRect = CoreFoundation.CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        // Draw cropped and scaled image
        let destRect = CoreFoundation.CGRect(x: 0, y: 0, width: CGFloat(newWidth), height: CGFloat(newHeight))

        // Clip to crop rect
        context.clip(to: [cropRect])

        // Draw the image
        let imageRect = CoreFoundation.CGRect(x: cropRect.origin.x, y: cropRect.origin.y, width: CGFloat(image.width), height: CGFloat(image.height))
        context.draw(image, in: imageRect)

        // Extract zoomed image
        guard let zoomedImage = context.makeImage() else {
            throw PreviewError.playbackFailed("Failed to create zoomed image")
        }

        return zoomedImage
    }
}
