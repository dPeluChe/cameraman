//
//  ExportOverlayRenderer.swift
//  EngineKit
//
//  Image and shape overlay burn-in for video export.
//  Extracted from ExportCaptionRenderer.swift.
//

import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import ImageIO

extension ExportEngine {

    // MARK: - Image Overlays

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

    func buildImageLayer(
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
        let y = (1.0 - CGFloat(position.y) - CGFloat(position.h)) * renderSize.height
        let w = CGFloat(position.w) * renderSize.width
        let h = CGFloat(position.h) * renderSize.height

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.frame = CoreFoundation.CGRect(x: x, y: y, width: w, height: h)
        imageLayer.opacity = Float(item.opacity)

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

    // MARK: - Combined Overlay Layer

    /// Create a combined animation tool with captions, image overlays, and shape overlays
    func createCombinedOverlayLayer(
        for project: Project,
        projectId: ProjectId,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime,
        burnCaptions: Bool
    ) async throws -> AVVideoCompositionCoreAnimationTool? {
        let hasCaptions = burnCaptions && project.captions != nil
        let hasImageOverlays = !project.mediaItems.filter { $0.type == .image }.isEmpty
        let hasShapeOverlays = !project.overlays.isEmpty

        guard hasCaptions || hasImageOverlays || hasShapeOverlays else {
            return nil
        }

        let parentLayer = CALayer()
        parentLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        if hasCaptions, let captionsConfig = project.captions {
            let projectDirectory = getProjectDirectory(for: projectId)
            let captionPath = projectDirectory.appendingPathComponent(captionsConfig.srtPath)

            if fileManager.fileExists(atPath: captionPath.path) {
                let captionsManager = CaptionsManager()
                try? await captionsManager.loadCaptions(from: captionPath.path)
                let captions = await captionsManager.getAllCaptions()
                let style = await captionsManager.getStyle()
                let fontSize = style.fontSize * CGFloat(renderSize.height)
                let font = NSFont(name: style.fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let yPos = (1.0 - style.verticalPosition) * CGFloat(renderSize.height) - fontSize
                let maxLineWidth = style.maxLineWidth * CGFloat(renderSize.width)

                let captionLayer = CALayer()
                captionLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
                parentLayer.addSublayer(captionLayer)

                for caption in captions {
                    let textLayer = buildCaptionTextLayer(
                        caption: caption, style: style, font: font, fontSize: fontSize,
                        yPos: yPos, maxLineWidth: maxLineWidth, renderSize: renderSize,
                        compositionDuration: compositionDuration
                    )
                    captionLayer.addSublayer(textLayer)
                }
            }
        }

        if hasImageOverlays {
            let projectDirectory = getProjectDirectory(for: projectId)
            let renderer = ImageOverlayRenderer(projectDirectory: projectDirectory)
            let imageItems = project.mediaItems.filter { $0.type == .image }

            let imageLayer = CALayer()
            imageLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(imageLayer)

            for item in imageItems {
                guard let layer = buildImageLayer(
                    item: item, renderer: renderer, renderSize: renderSize,
                    compositionDuration: compositionDuration
                ) else { continue }
                imageLayer.addSublayer(layer)
            }
        }

        if hasShapeOverlays {
            let shapeLayer = CALayer()
            shapeLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(shapeLayer)

            for overlay in project.overlays {
                guard let layer = buildShapeOverlayLayer(
                    overlay: overlay, renderSize: renderSize,
                    compositionDuration: compositionDuration
                ) else { continue }
                shapeLayer.addSublayer(layer)
            }
        }

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Combined overlay layer created (captions: \(hasCaptions), images: \(hasImageOverlays), shapes: \(hasShapeOverlays))")
        return animationTool
    }

    // MARK: - Shape Overlays

    /// Create shape overlay layer for burn-in shape overlays (arrow/rect/line/text)
    /// Deprecated: use createCombinedOverlayLayer instead
    @available(*, deprecated, message: "Use createCombinedOverlayLayer to build a unified layer tree")
    func createShapeOverlayLayer(
        for project: Project,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws -> AVVideoCompositionCoreAnimationTool? {
        let overlays = project.overlays
        guard !overlays.isEmpty else {
            logger.debug("No shape overlays in project, skipping")
            return nil
        }

        logger.debug("Creating shape overlay layer for \(overlays.count) overlays")

        let parentLayer = CALayer()
        parentLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = CALayer()
        overlayLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(overlayLayer)

        for overlay in overlays {
            guard let layer = buildShapeOverlayLayer(
                overlay: overlay,
                renderSize: renderSize,
                compositionDuration: compositionDuration
            ) else { continue }
            overlayLayer.addSublayer(layer)
        }

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Shape overlay layer created with \(overlays.count) overlays")
        return animationTool
    }

    func buildShapeOverlayLayer(
        overlay: Project.Overlay,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) -> CALayer? {
        let startTime = CMTime(seconds: overlay.start, preferredTimescale: 600)
        let endTime = CMTime(seconds: overlay.end, preferredTimescale: 600)
        let duration = endTime.seconds - startTime.seconds

        guard duration > 0 else { return nil }

        let shapeLayer = CALayer()
        shapeLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        let baseSize = OverlayBaseSize.size(for: overlay.type, canvasSize: renderSize)

        let scaledW = baseSize.width * overlay.transform.scale
        let scaledH = baseSize.height * overlay.transform.scale

        let cx = overlay.transform.x * renderSize.width
        let cy = (1.0 - overlay.transform.y) * renderSize.height

        let containerLayer = CALayer()
        containerLayer.frame = CoreFoundation.CGRect(
            x: cx - scaledW / 2,
            y: cy - scaledH / 2,
            width: scaledW,
            height: scaledH
        )

        if overlay.transform.rotation != 0 {
            containerLayer.transform = CATransform3DMakeRotation(CGFloat(overlay.transform.rotation) * .pi / 180.0, 0, 0, 1)
        }

        if overlay.style.shadow {
            containerLayer.shadowColor = NSColor.black.cgColor
            containerLayer.shadowOffset = CoreFoundation.CGSize(width: 4, height: 4)
            containerLayer.shadowRadius = 8
            containerLayer.shadowOpacity = 0.5
        }

        let strokeColor = NSColor(hex: overlay.style.stroke).cgColor
        let strokeWidth = overlay.style.strokeWidth * max(1, renderSize.width / 1920)

        switch overlay.type {
        case .arrow:
            let path = CGMutablePath()
            let shaftW = scaledW * 0.7
            let shaftH = scaledH * 0.2
            let headH = scaledH * 0.8

            path.move(to: CGPoint(x: -scaledW / 2, y: -shaftH / 2))
            path.addLine(to: CGPoint(x: shaftW / 2, y: -shaftH / 2))
            path.addLine(to: CGPoint(x: shaftW / 2, y: -headH / 2))
            path.addLine(to: CGPoint(x: scaledW / 2, y: 0))
            path.addLine(to: CGPoint(x: shaftW / 2, y: headH / 2))
            path.addLine(to: CGPoint(x: shaftW / 2, y: shaftH / 2))
            path.addLine(to: CGPoint(x: -scaledW / 2, y: shaftH / 2))
            path.closeSubpath()

            let shapePathLayer = CAShapeLayer()
            shapePathLayer.path = path
            shapePathLayer.fillColor = strokeColor
            shapePathLayer.frame = CoreFoundation.CGRect(origin: .zero, size: CGSize(width: scaledW, height: scaledH))
            containerLayer.addSublayer(shapePathLayer)

        case .rect:
            let rectLayer = CALayer()
            rectLayer.frame = CoreFoundation.CGRect(origin: .zero, size: CGSize(width: scaledW, height: scaledH))
            rectLayer.borderColor = strokeColor
            rectLayer.borderWidth = strokeWidth
            rectLayer.cornerRadius = 10 * overlay.transform.scale
            if let bg = overlay.style.bg {
                rectLayer.backgroundColor = NSColor(hex: bg).cgColor
            }
            containerLayer.addSublayer(rectLayer)

        case .line:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: scaledH / 2))
            path.addLine(to: CGPoint(x: scaledW, y: scaledH / 2))

            let shapePathLayer = CAShapeLayer()
            shapePathLayer.path = path
            shapePathLayer.strokeColor = strokeColor
            shapePathLayer.lineWidth = strokeWidth
            shapePathLayer.frame = CoreFoundation.CGRect(origin: .zero, size: CGSize(width: scaledW, height: scaledH))
            containerLayer.addSublayer(shapePathLayer)

        case .text:
            let fontSize = (overlay.style.size ?? 24) * max(1, renderSize.width / 1920)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
            let textLayer = CATextLayer()
            textLayer.string = overlay.style.text ?? "Text"
            textLayer.font = font
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = NSColor(hex: overlay.style.color ?? "#FFFFFF").cgColor
            textLayer.alignmentMode = .center
            textLayer.frame = CoreFoundation.CGRect(origin: .zero, size: CGSize(width: scaledW, height: scaledH))
            if let bg = overlay.style.bg {
                textLayer.backgroundColor = NSColor(hex: bg).cgColor
            }
            containerLayer.addSublayer(textLayer)
        }

        shapeLayer.addSublayer(containerLayer)

        let animation = overlay.animation
        switch animation?.type ?? .none {
        case .none:
            shapeLayer.opacity = 1.0
        case .fadeIn:
            shapeLayer.opacity = 0.0
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.duration = animation?.fadeInDuration ?? 0.3
            fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + startTime.seconds
            fadeIn.isRemovedOnCompletion = false
            fadeIn.fillMode = .forwards
            shapeLayer.add(fadeIn, forKey: "fadeIn_\(overlay.id.uuidString)")
        case .fadeOut:
            shapeLayer.opacity = 1.0
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = animation?.fadeOutDuration ?? 0.3
            fadeOut.beginTime = AVCoreAnimationBeginTimeAtZero + endTime.seconds - (animation?.fadeOutDuration ?? 0.3)
            fadeOut.isRemovedOnCompletion = false
            fadeOut.fillMode = .forwards
            shapeLayer.add(fadeOut, forKey: "fadeOut_\(overlay.id.uuidString)")
        case .fadeInOut:
            shapeLayer.opacity = 0.0
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.duration = animation?.fadeInDuration ?? 0.3
            fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + startTime.seconds
            fadeIn.isRemovedOnCompletion = false
            fadeIn.fillMode = .forwards
            shapeLayer.add(fadeIn, forKey: "fadeIn_\(overlay.id.uuidString)")

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = animation?.fadeOutDuration ?? 0.3
            fadeOut.beginTime = AVCoreAnimationBeginTimeAtZero + endTime.seconds - (animation?.fadeOutDuration ?? 0.3)
            fadeOut.isRemovedOnCompletion = false
            fadeOut.fillMode = .forwards
            shapeLayer.add(fadeOut, forKey: "fadeOut_\(overlay.id.uuidString)")
        case .drawOn:
            shapeLayer.opacity = 1.0
        }

        return shapeLayer
    }

    // MARK: - Deprecated

    @available(*, deprecated, message: "Use createCombinedOverlayLayer to build a unified layer tree upfront")
    func mergeAnimationTools(
        existing: AVVideoCompositionCoreAnimationTool,
        new: AVVideoCompositionCoreAnimationTool
    ) -> AVVideoCompositionCoreAnimationTool? {
        logger.warning("mergeAnimationTools is deprecated — use createCombinedOverlayLayer instead")
        return new
    }
}
