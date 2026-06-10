//
//  VideoExportSession+Composition.swift
//  EngineKit
//
//  Extracted from VideoExportSession.swift (Phase 1 refactor, v0.5.1).
//  Builds the AVMutableVideoComposition for export, handling fullscreen-camera,
//  standard, and per-segment masked paths.
//

import Foundation
import AVFoundation
import CoreGraphics

extension ExportEngine {
    /// Stage 4: Produce the AVMutableVideoComposition used by the export session.
    func buildExportVideoComposition(
        project: Project,
        preset: ExportPreset,
        options: ExportOptions,
        compositionResult: CompositionBuilder.Result,
        primarySources: Project.Sources
    ) async throws -> AVMutableVideoComposition {
        logger.debug("Setting up video composition with preset: \(preset.name)")

        let composition = compositionResult.composition
        let videoTrack = compositionResult.videoTrack
        let cameraTrack = compositionResult.cameraTrack

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CoreFoundation.CGSize(
            width: CGFloat(preset.output.width),
            height: CGFloat(preset.output.height)
        )
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(preset.output.fps))

        logger.debug("Render size: \(preset.output.width)x\(preset.output.height) @ \(preset.output.fps)fps")

        let screenMuted = options.videoMuteState?.screenMuted ?? false
        let cameraMuted = options.videoMuteState?.cameraMuted ?? false
        let videoOverlays = compositionResult.videoOverlaySources

        if screenMuted, let cameraTrack = cameraTrack, !cameraMuted {
            applyFullscreenCameraInstructions(
                videoComposition: videoComposition,
                composition: composition,
                videoTrack: videoTrack,
                cameraTrack: cameraTrack,
                project: project,
                primarySources: primarySources,
                options: options,
                videoOverlays: videoOverlays
            )
        } else {
            try await applyStandardExportInstructions(
                videoComposition: videoComposition,
                composition: composition,
                videoTrack: videoTrack,
                cameraTrack: cameraTrack,
                screenMuted: screenMuted,
                cameraMuted: cameraMuted,
                project: project,
                primarySources: primarySources,
                options: options,
                videoOverlays: videoOverlays
            )
        }

        return videoComposition
    }

    // MARK: - Fullscreen camera path

    /// Screen is muted and camera is visible: render the camera fullscreen, with optional mask.
    private func applyFullscreenCameraInstructions(
        videoComposition: AVMutableVideoComposition,
        composition: AVComposition,
        videoTrack: AVMutableCompositionTrack,
        cameraTrack: AVMutableCompositionTrack,
        project: Project,
        primarySources: Project.Sources,
        options: ExportOptions,
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) {
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setOpacity(0, at: .zero)

        let trackSize = cameraTrack.naturalSize
        let cameraSourceSize = CoreFoundation.CGSize(
            width: trackSize.width > 0 ? trackSize.width : CGFloat(primarySources.camera?.size.w ?? 1280),
            height: trackSize.height > 0 ? trackSize.height : CGFloat(primarySources.camera?.size.h ?? 720)
        )
        let camScale = min(
            videoComposition.renderSize.width / cameraSourceSize.width,
            videoComposition.renderSize.height / cameraSourceSize.height
        )
        let camOffX = (videoComposition.renderSize.width - cameraSourceSize.width * camScale) / 2
        let camOffY = (videoComposition.renderSize.height - cameraSourceSize.height * camScale) / 2
        var cameraTransform = CGAffineTransform.identity
        cameraTransform = cameraTransform.translatedBy(x: camOffX, y: camOffY)
        cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)

        let maskShape = project.canvas.layout.camera?.maskShape ?? .none
        let cornerRadius = project.canvas.layout.camera?.cornerRadius ?? 0

        if maskShape != .none || !videoOverlays.isEmpty {
            let maskedInstruction = MaskedVideoCompositionInstruction(
                timeRange: CMTimeRangeMake(start: .zero, duration: composition.duration),
                screenTrackID: videoTrack.trackID,
                cameraTrackID: cameraTrack.trackID,
                renderSize: videoComposition.renderSize,
                screenTransform: .identity,
                cameraTransform: cameraTransform,
                cameraRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                maskShape: maskShape,
                cornerRadius: CGFloat(cornerRadius),
                layoutType: "fullscreenCamera",
                screenMuted: true,
                zoomPlan: options.applyZoom ? options.zoomPlan : nil,
                videoOverlays: videoOverlays
            )
            videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
            videoComposition.instructions = [maskedInstruction]
        } else {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)
            instruction.layerInstructions = [cameraLayerInstruction, layerInstruction]
            videoComposition.instructions = [instruction]
        }
    }

    // MARK: - Standard path (screen visible, optional camera overlay)

    private func applyStandardExportInstructions(
        videoComposition: AVMutableVideoComposition,
        composition: AVComposition,
        videoTrack: AVMutableCompositionTrack,
        cameraTrack: AVMutableCompositionTrack?,
        screenMuted: Bool,
        cameraMuted: Bool,
        project: Project,
        primarySources: Project.Sources,
        options: ExportOptions,
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) async throws {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        if screenMuted {
            layerInstruction.setOpacity(0, at: .zero)
        }

        // Downscale from native resolution to output resolution.
        // NOTE: all clips are assumed to share the resolution of the primary sources.
        let sourceSize = CoreFoundation.CGSize(
            width: CGFloat(primarySources.screen.size.w),
            height: CGFloat(primarySources.screen.size.h)
        )
        logger.debug("Source size: \(primarySources.screen.size.w)x\(primarySources.screen.size.h)")

        let transform = calculateDownscaleTransform(
            from: sourceSize,
            to: videoComposition.renderSize,
            contentMode: project.canvas.background.fitMode ?? "fill"
        )

        if options.applyZoom, let zoomPlan = options.zoomPlan {
            logger.debug("Applying zoom transforms with \(zoomPlan.keyframes.count) keyframes")
            try await applyZoomTransforms(
                to: layerInstruction,
                zoomPlan: zoomPlan,
                baseTransform: transform,
                sourceSize: sourceSize,
                renderSize: videoComposition.renderSize,
                compositionDuration: composition.duration
            )
        } else {
            layerInstruction.setTransform(transform, at: .zero)
        }

        // Optional camera overlay
        if !cameraMuted, let cameraTrack = cameraTrack, let defaultCamera = project.canvas.layout.camera {
            let trackSize = cameraTrack.naturalSize
            let cameraSourceSize = CoreFoundation.CGSize(
                width: trackSize.width > 0 ? trackSize.width : CGFloat(primarySources.camera?.size.w ?? 1280),
                height: trackSize.height > 0 ? trackSize.height : CGFloat(primarySources.camera?.size.h ?? 720)
            )

            let hasPerSegmentCamera = project.timeline.segments.contains { $0.cameraPosition != nil }

            if hasPerSegmentCamera || defaultCamera.maskShape != .none {
                let maskedInstructions = buildExportPerSegmentInstructions(
                    project: project,
                    composition: composition,
                    videoTrack: videoTrack,
                    cameraTrack: cameraTrack,
                    videoComposition: videoComposition,
                    cameraSourceSize: cameraSourceSize,
                    screenTransform: transform,
                    defaultCamera: defaultCamera,
                    options: options,
                    videoOverlays: videoOverlays
                )
                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = maskedInstructions
                logger.debug("Export: \(maskedInstructions.count) per-segment compositor instructions")
            } else if !videoOverlays.isEmpty {
                // Imported-video overlays need the custom compositor (zoom included via zoomPlan)
                let cameraTransform = calculateCameraOverlayTransform(
                    cameraPosition: defaultCamera,
                    cameraSourceSize: cameraSourceSize,
                    renderSize: videoComposition.renderSize
                )
                applyCompositorInstruction(
                    videoComposition: videoComposition,
                    composition: composition,
                    project: project,
                    screenTrackID: videoTrack.trackID,
                    cameraTrackID: cameraTrack.trackID,
                    screenTransform: transform,
                    cameraTransform: cameraTransform,
                    screenMuted: screenMuted,
                    options: options,
                    videoOverlays: videoOverlays
                )
            } else {
                // Standard PiP (no mask, uniform across timeline).
                let cameraTransform = calculateCameraOverlayTransform(
                    cameraPosition: defaultCamera,
                    cameraSourceSize: cameraSourceSize,
                    renderSize: videoComposition.renderSize
                )
                let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
                cameraLayerInstruction.setTransform(cameraTransform, at: .zero)
                instruction.layerInstructions = [cameraLayerInstruction, layerInstruction]
                videoComposition.instructions = [instruction]
            }
        } else if !videoOverlays.isEmpty {
            applyCompositorInstruction(
                videoComposition: videoComposition,
                composition: composition,
                project: project,
                screenTrackID: videoTrack.trackID,
                cameraTrackID: nil,
                screenTransform: transform,
                cameraTransform: nil,
                screenMuted: screenMuted,
                options: options,
                videoOverlays: videoOverlays
            )
        } else {
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
        }
    }

    /// Single full-range compositor instruction — used when imported-video overlays
    /// force the custom compositor on what would otherwise be a layer-instruction path.
    private func applyCompositorInstruction(
        videoComposition: AVMutableVideoComposition,
        composition: AVComposition,
        project: Project,
        screenTrackID: CMPersistentTrackID,
        cameraTrackID: CMPersistentTrackID?,
        screenTransform: CGAffineTransform,
        cameraTransform: CGAffineTransform?,
        screenMuted: Bool,
        options: ExportOptions,
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource]
    ) {
        let maskedInstruction = MaskedVideoCompositionInstruction(
            timeRange: CMTimeRangeMake(start: .zero, duration: composition.duration),
            screenTrackID: screenTrackID,
            cameraTrackID: cameraTrackID,
            renderSize: videoComposition.renderSize,
            screenTransform: screenTransform,
            cameraTransform: cameraTransform,
            cameraRect: nil,
            maskShape: .none,
            cornerRadius: 0,
            layoutType: project.canvas.layout.type,
            screenMuted: screenMuted,
            videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
            videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
            padding: CGFloat(project.canvas.padding),
            backgroundType: project.canvas.background.type,
            backgroundValue: project.canvas.background.value,
            zoomPlan: options.applyZoom ? options.zoomPlan : nil,
            videoOverlays: videoOverlays
        )
        videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
        videoComposition.instructions = [maskedInstruction]
    }

    // MARK: - Per-segment masked instructions

    private func buildExportPerSegmentInstructions(
        project: Project,
        composition: AVComposition,
        videoTrack: AVMutableCompositionTrack,
        cameraTrack: AVMutableCompositionTrack,
        videoComposition: AVMutableVideoComposition,
        cameraSourceSize: CGSize,
        screenTransform: CGAffineTransform,
        defaultCamera: Project.Canvas.Layout.CameraPosition,
        options: ExportOptions,
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) -> [MaskedVideoCompositionInstruction] {
        var maskedInstructions: [MaskedVideoCompositionInstruction] = []
        let totalDuration = composition.duration
        let zoomPlan = options.applyZoom ? options.zoomPlan : nil

        for (i, segment) in project.timeline.segments.enumerated() {
            let segCamera = segment.cameraPosition ?? defaultCamera
            let segCameraTransform = PreviewEngine.cameraTransform(
                position: segCamera,
                camSourceSize: cameraSourceSize,
                renderSize: videoComposition.renderSize
            )

            let segStart: CMTime
            if let prev = maskedInstructions.last {
                segStart = CMTimeRangeGetEnd(prev.timeRange)
            } else {
                segStart = .zero
            }
            let segEnd: CMTime
            if i == project.timeline.segments.count - 1 {
                segEnd = totalDuration
            } else {
                segEnd = CMTime(seconds: segment.timelineIn + segment.timelineDuration, preferredTimescale: 600)
            }
            let segDuration = CMTimeSubtract(segEnd, segStart)

            maskedInstructions.append(MaskedVideoCompositionInstruction(
                timeRange: CMTimeRangeMake(start: segStart, duration: segDuration),
                screenTrackID: videoTrack.trackID,
                cameraTrackID: cameraTrack.trackID,
                renderSize: videoComposition.renderSize,
                screenTransform: screenTransform,
                cameraTransform: segCameraTransform,
                cameraRect: CGRect(x: segCamera.x, y: segCamera.y, width: segCamera.w, height: segCamera.h),
                maskShape: segCamera.maskShape,
                cornerRadius: CGFloat(segCamera.cornerRadius),
                layoutType: project.canvas.layout.type,
                videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                padding: CGFloat(project.canvas.padding),
                backgroundType: project.canvas.background.type,
                backgroundValue: project.canvas.background.value,
                cameraBorderWidth: CGFloat(segCamera.borderWidth),
                cameraBorderColor: segCamera.borderColor,
                zoomPlan: zoomPlan,
                videoOverlays: videoOverlays
            ))
        }

        return maskedInstructions
    }
}
