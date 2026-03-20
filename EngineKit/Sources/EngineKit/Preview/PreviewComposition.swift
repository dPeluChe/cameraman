//
//  PreviewComposition.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

extension PreviewEngine {
    /// Build an AVMutableVideoComposition with screen + camera layer transforms
    /// Reusable for both initial creation and live updates
    func buildVideoComposition(for project: Project, composition: AVComposition) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()

        let renderSize = CoreFoundation.CGSize(
            width: CGFloat(project.canvas.format.w),
            height: CGFloat(project.canvas.format.h)
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        // Find video tracks in composition
        let videoTracks = composition.tracks(withMediaType: .video)
        guard let screenTrack = videoTracks.first else {
            videoComposition.instructions = [instruction]
            return videoComposition
        }

        // Screen layer instruction
        let screenLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: screenTrack)
        let screenSize = screenTrack.naturalSize
        let screenSourceSize = CoreFoundation.CGSize(
            width: screenSize.width > 0 ? screenSize.width : 1920,
            height: screenSize.height > 0 ? screenSize.height : 1080
        )

        let scaleX = renderSize.width / screenSourceSize.width
        let scaleY = renderSize.height / screenSourceSize.height
        let scale = min(scaleX, scaleY)
        let offsetX = (renderSize.width - screenSourceSize.width * scale) / 2
        let offsetY = (renderSize.height - screenSourceSize.height * scale) / 2

        var screenTransform = CGAffineTransform.identity
        screenTransform = screenTransform.translatedBy(x: offsetX, y: offsetY)
        screenTransform = screenTransform.scaledBy(x: scale, y: scale)
        screenLayerInstruction.setTransform(screenTransform, at: .zero)

        // Camera layer instruction (if second video track exists)
        if videoTracks.count > 1, let cameraPosition = project.canvas.layout.camera {
            let cameraTrack = videoTracks[1]
            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)

            let camNaturalSize = cameraTrack.naturalSize
            let cameraSourceSize = CoreFoundation.CGSize(
                width: camNaturalSize.width > 0 ? camNaturalSize.width : 1280,
                height: camNaturalSize.height > 0 ? camNaturalSize.height : 720
            )

            let cameraW = cameraPosition.w * renderSize.width
            let cameraH = cameraPosition.h * renderSize.height
            let camScaleX = cameraW / cameraSourceSize.width
            let camScaleY = cameraH / cameraSourceSize.height
            let camScale = min(camScaleX, camScaleY)

            let camScaledW = cameraSourceSize.width * camScale
            let camScaledH = cameraSourceSize.height * camScale
            let camX = cameraPosition.x * renderSize.width + (cameraW - camScaledW) / 2
            let camY = cameraPosition.y * renderSize.height + (cameraH - camScaledH) / 2

            var cameraTransform = CGAffineTransform.identity
            cameraTransform = cameraTransform.translatedBy(x: camX, y: camY)
            cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)
            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)

            // Camera on top
            instruction.layerInstructions = [cameraLayerInstruction, screenLayerInstruction]
        } else {
            instruction.layerInstructions = [screenLayerInstruction]
        }

        videoComposition.instructions = [instruction]
        return videoComposition
    }

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

        let videoComposition = buildVideoComposition(for: project, composition: composition)

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
