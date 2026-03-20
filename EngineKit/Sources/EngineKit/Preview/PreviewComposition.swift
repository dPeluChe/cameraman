//
//  PreviewComposition.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

extension PreviewEngine {
    /// Resolve sources for a specific take ID, falling back to primary sources
    func resolveSources(for takeId: UUID?) -> Project.Sources? {
        if let takeId = takeId, let take = project?.takes.first(where: { $0.id == takeId }) {
            return take.sources
        }
        return project?.primarySources
    }

    /// Create AVPlayer with composition that applies edits
    func createPlayerWithEdits() async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard project.primarySources != nil else {
            throw PreviewError.playbackFailed("No sources found")
        }

        guard let projectDir = projectDirectory else {
            throw PreviewError.playbackFailed("No project directory set")
        }

        logger.debug("Creating player with edits - project: \(project.name), segments: \(project.timeline.segments.count)")

        // Build composition using shared CompositionBuilder
        let builder = CompositionBuilder(fileManager: fileManager)

        let resolver = CompositionBuilder.SourceResolver(
            projectDirectory: URL(fileURLWithPath: projectDir),
            screenProxyPath: configuration.useProxy ? getProxyPath(for: "screen") : nil,
            cameraProxyPath: configuration.useProxy ? getProxyPath(for: "camera") : nil
        )

        logger.debug("Resolver projectDirectory: \(projectDir)")
        if let sources = project.primarySources {
            let screenFullPath = URL(fileURLWithPath: projectDir).appendingPathComponent(sources.screen.path).path
            logger.debug("Screen source path: \(sources.screen.path)")
            logger.debug("Screen full path: \(screenFullPath)")
            logger.debug("Screen file exists: \(self.fileManager.fileExists(atPath: screenFullPath))")
        }

        let result: CompositionBuilder.Result
        do {
            result = try await builder.buildComposition(
                project: project,
                resolver: resolver,
                resolveSources: { [self] segment in
                    self.resolveSources(for: segment.takeId)
                }
            )
        } catch {
            logger.error("Failed to build composition: \(error.localizedDescription)")
            throw PreviewError.playbackFailed("Preview failed: \(error.localizedDescription)")
        }

        let composition = result.composition

        // Build video composition for layout/transforms
        let videoComposition = AVMutableVideoComposition()

        let renderSize = CoreFoundation.CGSize(
            width: CGFloat(project.canvas.format.w),
            height: CGFloat(project.canvas.format.h)
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        // Screen layer instruction — scale to fill canvas
        let screenLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: result.videoTrack)

        // Use actual track dimensions for correct transform
        let screenTrackSize = result.videoTrack.naturalSize
        let screenSourceSize = CoreFoundation.CGSize(
            width: screenTrackSize.width > 0 ? screenTrackSize.width : CGFloat(project.primarySources?.screen.size.w ?? 1920),
            height: screenTrackSize.height > 0 ? screenTrackSize.height : CGFloat(project.primarySources?.screen.size.h ?? 1080)
        )
        logger.debug("[PREVIEW-DEBUG] Screen actual size: \(Int(screenSourceSize.width))x\(Int(screenSourceSize.height))")

        let scaleX = renderSize.width / screenSourceSize.width
        let scaleY = renderSize.height / screenSourceSize.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = screenSourceSize.width * scale
        let scaledHeight = screenSourceSize.height * scale

        let offsetX = (renderSize.width - scaledWidth) / 2
        let offsetY = (renderSize.height - scaledHeight) / 2

        var screenTransform = CGAffineTransform.identity
        screenTransform = screenTransform.translatedBy(x: offsetX, y: offsetY)
        screenTransform = screenTransform.scaledBy(x: scale, y: scale)

        screenLayerInstruction.setTransform(screenTransform, at: .zero)

        // Camera layer instruction if camera track exists
        if let cameraTrack = result.cameraTrack, let cameraPosition = project.canvas.layout.camera {
            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)

            // Use actual track dimensions (not project metadata which may be wrong)
            let trackSize = cameraTrack.naturalSize
            let cameraSourceSize = CoreFoundation.CGSize(
                width: trackSize.width > 0 ? trackSize.width : CGFloat(project.primarySources?.camera?.size.w ?? 1280),
                height: trackSize.height > 0 ? trackSize.height : CGFloat(project.primarySources?.camera?.size.h ?? 720)
            )
            logger.debug("[PREVIEW-DEBUG] Camera actual size: \(Int(cameraSourceSize.width))x\(Int(cameraSourceSize.height))")

            let cameraX = cameraPosition.x * renderSize.width
            let cameraY = cameraPosition.y * renderSize.height
            let cameraW = cameraPosition.w * renderSize.width
            let cameraH = cameraPosition.h * renderSize.height

            let camScaleX = cameraW / cameraSourceSize.width
            let camScaleY = cameraH / cameraSourceSize.height
            let camScale = min(camScaleX, camScaleY)

            let camScaledWidth = cameraSourceSize.width * camScale
            let camScaledHeight = cameraSourceSize.height * camScale

            let camOffsetX = cameraX + (cameraW - camScaledWidth) / 2
            let camOffsetY = cameraY + (cameraH - camScaledHeight) / 2

            var cameraTransform = CGAffineTransform.identity
            cameraTransform = cameraTransform.translatedBy(x: camOffsetX, y: camOffsetY)
            cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)

            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)

            instruction.layerInstructions = [screenLayerInstruction, cameraLayerInstruction]
        } else {
            instruction.layerInstructions = [screenLayerInstruction]
        }

        videoComposition.instructions = [instruction]

        logger.debug("[PREVIEW-DEBUG] Video composition: \(instruction.layerInstructions.count) layers, render=\(Int(renderSize.width))x\(Int(renderSize.height))")
        if result.cameraTrack != nil {
            logger.debug("[PREVIEW-DEBUG] Camera track present, PiP position: x=\(project.canvas.layout.camera?.x ?? -1), y=\(project.canvas.layout.camera?.y ?? -1), w=\(project.canvas.layout.camera?.w ?? -1), h=\(project.canvas.layout.camera?.h ?? -1)")
        } else {
            logger.debug("[PREVIEW-DEBUG] No camera track in composition")
        }

        // Create player item
        let playerItem = await MainActor.run {
            let item = AVPlayerItem(asset: composition)
            item.videoComposition = videoComposition
            return item
        }
        player = AVPlayer(playerItem: playerItem)
        self.composition = composition
        self.videoCompositionConfig = videoComposition

        logger.debug("Player created successfully with composition")
    }
}
