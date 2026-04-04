//
//  ExportCaptionRenderer.swift
//  EngineKit
//
//  Extracted from VideoExportSession.swift — caption burn-in logic
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import AppKit
import ImageIO

extension ExportEngine {
    /// Create caption layer for burn-in captions
    func createCaptionLayer(
        for project: Project,
        projectId: ProjectId,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws -> AVVideoCompositionCoreAnimationTool {
        logger.debug("Creating caption layer for burn-in")

        guard let captionsConfig = project.captions else {
            logger.warning("No captions configured in project")
            throw ExportError.exportFailed("No captions available for burn-in")
        }

        let projectDirectory = getProjectDirectory(for: projectId)
        let captionPath = projectDirectory.appendingPathComponent(captionsConfig.srtPath)

        guard fileManager.fileExists(atPath: captionPath.path) else {
            logger.error("Caption file not found: \(captionPath)")
            throw ExportError.sourceFileNotFound(captionsConfig.srtPath)
        }

        let captionsManager = CaptionsManager()
        try await captionsManager.loadCaptions(from: captionPath.path)
        let captions = await captionsManager.getAllCaptions()

        logger.debug("Loaded \(captions.count) captions for burn-in")

        // Create layer hierarchy: parent -> video + captions
        let parentLayer = CALayer()
        parentLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let captionLayer = CALayer()
        captionLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(captionLayer)

        let style = await captionsManager.getStyle()
        let fontSize = style.fontSize * CGFloat(renderSize.height)
        let font = NSFont(name: style.fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let yPos = (1.0 - style.verticalPosition) * CGFloat(renderSize.height) - fontSize
        let maxLineWidth = style.maxLineWidth * CGFloat(renderSize.width)

        for caption in captions {
            let textLayer = buildCaptionTextLayer(
                caption: caption,
                style: style,
                font: font,
                fontSize: fontSize,
                yPos: yPos,
                maxLineWidth: maxLineWidth,
                renderSize: renderSize,
                compositionDuration: compositionDuration
            )
            captionLayer.addSublayer(textLayer)
        }

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Caption layer created with \(captions.count) captions")
        return animationTool
    }

    /// Build a single caption text layer with animations
    private func buildCaptionTextLayer(
        caption: CaptionsManager.CaptionEntry,
        style: CaptionsManager.CaptionStyle,
        font: NSFont,
        fontSize: CGFloat,
        yPos: CGFloat,
        maxLineWidth: CGFloat,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) -> CATextLayer {
        let startTime = CMTime(seconds: caption.start, preferredTimescale: 600)
        let endTime = CMTime(seconds: caption.end, preferredTimescale: 600)

        let textLayer = CATextLayer()
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor(hex: style.textColor).cgColor

        // Background
        if style.backgroundOpacity > 0 {
            let bgColor = NSColor(hex: style.backgroundColor).withAlphaComponent(style.backgroundOpacity)
            textLayer.backgroundColor = bgColor.cgColor
            textLayer.cornerRadius = fontSize * 0.2
        }

        // Shadow
        if style.shadow {
            textLayer.shadowColor = NSColor.black.cgColor
            textLayer.shadowOffset = CoreFoundation.CGSize(width: 0, height: -1)
            textLayer.shadowRadius = 2
            textLayer.shadowOpacity = 0.5
        }

        // Alignment and X position
        let xPos: CGFloat
        switch style.horizontalAlignment {
        case 0.0:
            textLayer.alignmentMode = .left
            xPos = CGFloat(renderSize.width) * (1.0 - style.maxLineWidth) / 2.0
        case 1.0:
            textLayer.alignmentMode = .right
            xPos = CGFloat(renderSize.width) * (1.0 + style.maxLineWidth) / 2.0
        default:
            textLayer.alignmentMode = .center
            xPos = CGFloat(renderSize.width) * 0.5
        }

        // Wrap and measure text
        let wrappedText = wrapText(caption.text, font: font, maxWidth: maxLineWidth)
        textLayer.string = wrappedText
        let textSize = (wrappedText as NSString).size(withAttributes: [.font: font])

        let textX = xPos - textSize.width / 2.0
        let textY = yPos - textSize.height
        textLayer.frame = CoreFoundation.CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

        // Animations
        textLayer.opacity = 0.0
        applyCaptionAnimations(
            to: textLayer,
            captionId: caption.id,
            startTime: startTime,
            endTime: endTime,
            compositionDuration: compositionDuration
        )

        return textLayer
    }

    /// Apply fade-in/hold/fade-out animation group to a caption layer
    private func applyCaptionAnimations(
        to textLayer: CATextLayer,
        captionId: Int,
        startTime: CMTime,
        endTime: CMTime,
        compositionDuration: CMTime
    ) {
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.2
        fadeIn.beginTime = startTime.seconds
        fadeIn.isRemovedOnCompletion = false
        fadeIn.fillMode = .forwards

        let hold = CABasicAnimation(keyPath: "opacity")
        hold.fromValue = 1.0
        hold.toValue = 1.0
        hold.beginTime = startTime.seconds + 0.2
        hold.duration = max(0, endTime.seconds - startTime.seconds - 0.4)
        hold.isRemovedOnCompletion = false
        hold.fillMode = .forwards

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.2
        fadeOut.beginTime = max(startTime.seconds + 0.2, endTime.seconds - 0.2)
        fadeOut.isRemovedOnCompletion = false
        fadeOut.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [fadeIn, hold, fadeOut]
        group.duration = compositionDuration.seconds
        group.isRemovedOnCompletion = false
        group.fillMode = .both
        group.beginTime = AVCoreAnimationBeginTimeAtZero

        textLayer.add(group, forKey: "caption_\(captionId)")
    }

    /// Wrap text to fit within max width
    func wrapText(_ text: String, font: NSFont, maxWidth: CGFloat) -> NSString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        var currentRange = CFRange(location: 0, length: attributedString.length)
        var lines: [String] = []

        while currentRange.length > 0 {
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                currentRange,
                nil,
                CoreFoundation.CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
                nil
            )

            let path = CGPath(rect: CoreFoundation.CGRect(origin: .zero, size: suggestedSize), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

            let lineRange = CTFrameGetVisibleStringRange(frame)
            let nsRange = NSRange(location: lineRange.location, length: lineRange.length)
            let lineText = attributedString.attributedSubstring(from: nsRange).string
            lines.append(lineText)

            currentRange.location += lineRange.length
            currentRange.length -= lineRange.length
        }

        return lines.joined(separator: "\n") as NSString
    }

    /// Create image overlay layer for burn-in image overlays
    func createImageOverlayLayer(
        for project: Project,
        projectId: ProjectId,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws -> AVVideoCompositionCoreAnimationTool? {
        let imageItems = project.mediaItems.filter { $0.type == .image }
        guard !imageItems.isEmpty else {
            logger.debug("No image overlays in project, skipping")
            return nil
        }

        logger.debug("Creating image overlay layer for \(imageItems.count) images")

        let projectDirectory = getProjectDirectory(for: projectId)
        let renderer = ImageOverlayRenderer(projectDirectory: projectDirectory)

        // Create layer hierarchy: parent -> video + images
        let parentLayer = CALayer()
        parentLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let imageLayer = CALayer()
        imageLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(imageLayer)

        for item in imageItems {
            guard let layer = buildImageLayer(
                item: item,
                renderer: renderer,
                renderSize: renderSize,
                compositionDuration: compositionDuration
            ) else { continue }
            imageLayer.addSublayer(layer)
        }

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Image overlay layer created with \(imageItems.count) images")
        return animationTool
    }

    /// Build a single image layer with visibility animations
    private func buildImageLayer(
        item: Project.MediaItem,
        renderer: ImageOverlayRenderer,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) -> CALayer? {
        guard let projectDir = renderer.projectDirectory else { return nil }

        let imageURL = projectDir.appendingPathComponent(item.path)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger.warning("Failed to load image: \(item.path)")
            return nil
        }

        let position = item.position ?? .defaultOverlay
        let x = CGFloat(position.x) * renderSize.width
        // CALayer origin is bottom-left, position.y is top-down normalized
        let y = (1.0 - CGFloat(position.y) - CGFloat(position.h)) * renderSize.height
        let w = CGFloat(position.w) * renderSize.width
        let h = CGFloat(position.h) * renderSize.height

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.frame = CoreFoundation.CGRect(x: x, y: y, width: w, height: h)
        imageLayer.opacity = Float(item.opacity)

        // Animate visibility based on timeline position
        let startTime = CMTime(seconds: item.timelineIn, preferredTimescale: 600)
        let endTime = CMTime(seconds: item.timelineOut, preferredTimescale: 600)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = Float(item.opacity)
        fadeIn.duration = 0.2
        fadeIn.beginTime = startTime.seconds
        fadeIn.isRemovedOnCompletion = false
        fadeIn.fillMode = .forwards

        let hold = CABasicAnimation(keyPath: "opacity")
        hold.fromValue = Float(item.opacity)
        hold.toValue = Float(item.opacity)
        hold.beginTime = startTime.seconds + 0.2
        hold.duration = max(0, item.duration - 0.4)
        hold.isRemovedOnCompletion = false
        hold.fillMode = .forwards

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Float(item.opacity)
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.2
        fadeOut.beginTime = max(startTime.seconds + 0.2, endTime.seconds - 0.2)
        fadeOut.isRemovedOnCompletion = false
        fadeOut.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [fadeIn, hold, fadeOut]
        group.duration = compositionDuration.seconds
        group.isRemovedOnCompletion = false
        group.fillMode = .both
        group.beginTime = AVCoreAnimationBeginTimeAtZero

        imageLayer.add(group, forKey: "image_\(item.id.uuidString)")

        return imageLayer
    }

    /// Merge two animation tools (captions + image overlays)
    func mergeAnimationTools(
        existing: AVVideoCompositionCoreAnimationTool,
        new: AVVideoCompositionCoreAnimationTool
    ) -> AVVideoCompositionCoreAnimationTool? {
        // AVVideoCompositionCoreAnimationTool doesn't expose layers directly
        // When both captions and overlays exist, overlays take priority — captions are lost
        // TODO: Implement proper merge by composing both into a shared parent CALayer
        logger.warning("Image overlays and burn-in captions cannot be combined yet — captions will be omitted in this export")
        return new
    }
}
