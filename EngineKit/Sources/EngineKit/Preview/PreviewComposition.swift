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
    /// - Parameter staticClips: non-recording clips from CompositionBuilder that need compositor rendering
    func buildVideoComposition(
        for project: Project,
        composition: AVComposition,
        staticClips: [CompositionBuilder.StaticClipInfo] = []
    ) -> AVMutableVideoComposition {
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

        let screenLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: screenTrack)
        let screenMuted = mutedVideoTracks.contains(.screen)
        let cameraMuted = mutedVideoTracks.contains(.camera)
        if screenMuted {
            screenLayerInstruction.setOpacity(0, at: .zero)
        }
        let screenSize = screenTrack.naturalSize
        let screenSourceSize = CoreFoundation.CGSize(
            width: screenSize.width > 0 ? screenSize.width : 1920,
            height: screenSize.height > 0 ? screenSize.height : 1080
        )

        let layoutType = project.canvas.layout.type
        let hasCameraTrack = videoTracks.count > 1

        // When screen is muted and camera is available, show camera fullscreen (with mask if set)
        if screenMuted && hasCameraTrack && !cameraMuted {
            let cameraTrack = videoTracks[1]
            let camNatural = cameraTrack.naturalSize
            let camSourceSize = CoreFoundation.CGSize(
                width: camNatural.width > 0 ? camNatural.width : 1280,
                height: camNatural.height > 0 ? camNatural.height : 720
            )
            let camScale = min(renderSize.width / camSourceSize.width, renderSize.height / camSourceSize.height)
            let camOffX = (renderSize.width - camSourceSize.width * camScale) / 2
            let camOffY = (renderSize.height - camSourceSize.height * camScale) / 2
            var cameraTransform = CGAffineTransform.identity
            cameraTransform = cameraTransform.translatedBy(x: camOffX, y: camOffY)
            cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)

            let maskShape = project.canvas.layout.camera?.maskShape ?? .none
            let cornerRadius = project.canvas.layout.camera?.cornerRadius ?? 0
            let overlayConfigs = project.overlays.map { OverlayConfig(overlay: $0) }

            if maskShape != .none {
                let maskedInstruction = MaskedVideoCompositionInstruction(
                    timeRange: CMTimeRangeMake(start: .zero, duration: composition.duration),
                    screenTrackID: screenTrack.trackID,
                    cameraTrackID: cameraTrack.trackID,
                    renderSize: renderSize,
                    screenTransform: CGAffineTransform.identity,
                    cameraTransform: cameraTransform,
                    cameraRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    maskShape: maskShape,
                    cornerRadius: CGFloat(cornerRadius),
                    layoutType: "fullscreenCamera",
                    screenMuted: true,
                    overlays: overlayConfigs
                )
                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = [maskedInstruction]
            } else {
                let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
                cameraLayerInstruction.setTransform(cameraTransform, at: .zero)
                instruction.layerInstructions = [cameraLayerInstruction, screenLayerInstruction]
                videoComposition.instructions = [instruction]
            }
            return videoComposition
        }

        if layoutType == "sideBySide" && hasCameraTrack && !cameraMuted {
            // Side-by-Side: screen on left 50%, camera on right 50%
            let halfWidth = renderSize.width / 2

            // Screen fills left half
            let screenScale = min(halfWidth / screenSourceSize.width, renderSize.height / screenSourceSize.height)
            let screenScaledW = screenSourceSize.width * screenScale
            let screenScaledH = screenSourceSize.height * screenScale
            let screenOffX = (halfWidth - screenScaledW) / 2
            let screenOffY = (renderSize.height - screenScaledH) / 2

            var screenTransform = CGAffineTransform.identity
            screenTransform = screenTransform.translatedBy(x: screenOffX, y: screenOffY)
            screenTransform = screenTransform.scaledBy(x: screenScale, y: screenScale)
            screenLayerInstruction.setTransform(screenTransform, at: .zero)

            // Camera fills right half
            let cameraTrack = videoTracks[1]
            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
            let camNatural = cameraTrack.naturalSize
            let camSourceSize = CoreFoundation.CGSize(
                width: camNatural.width > 0 ? camNatural.width : 1280,
                height: camNatural.height > 0 ? camNatural.height : 720
            )

            let camScale = min(halfWidth / camSourceSize.width, renderSize.height / camSourceSize.height)
            let camScaledW = camSourceSize.width * camScale
            let camScaledH = camSourceSize.height * camScale
            let camOffX = halfWidth + (halfWidth - camScaledW) / 2
            let camOffY = (renderSize.height - camScaledH) / 2

            var cameraTransform = CGAffineTransform.identity
            cameraTransform = cameraTransform.translatedBy(x: camOffX, y: camOffY)
            cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)
            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)

            instruction.layerInstructions = [cameraLayerInstruction, screenLayerInstruction]

            // If there are overlays, use the custom compositor
            if !project.overlays.isEmpty {
                let overlayConfigs = project.overlays.map { OverlayConfig(overlay: $0) }
                let maskedInstruction = MaskedVideoCompositionInstruction(
                    timeRange: instruction.timeRange,
                    screenTrackID: screenTrack.trackID,
                    cameraTrackID: cameraTrack.trackID,
                    renderSize: renderSize,
                    screenTransform: screenTransform,
                    cameraTransform: cameraTransform,
                    cameraRect: nil,
                    maskShape: .none,
                    cornerRadius: 0,
                    layoutType: "sideBySide",
                    screenMuted: screenMuted,
                    videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                    videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                    padding: CGFloat(project.canvas.padding),
                    backgroundType: project.canvas.background.type,
                    backgroundValue: project.canvas.background.value,
                    cameraBorderWidth: 0,
                    cameraBorderColor: "#FFFFFF",
                    overlays: overlayConfigs
                )
                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = [maskedInstruction]
                return videoComposition
            }

        } else {
            // Default / PiP / Fullscreen: screen fills canvas
            let scale = min(renderSize.width / screenSourceSize.width, renderSize.height / screenSourceSize.height)
            let offsetX = (renderSize.width - screenSourceSize.width * scale) / 2
            let offsetY = (renderSize.height - screenSourceSize.height * scale) / 2

            var screenTransform = CGAffineTransform.identity
            screenTransform = screenTransform.translatedBy(x: offsetX, y: offsetY)
            screenTransform = screenTransform.scaledBy(x: scale, y: scale)
            screenLayerInstruction.setTransform(screenTransform, at: .zero)

            // PiP camera overlay (skip if camera is muted)
            if hasCameraTrack && !cameraMuted, let defaultCamera = project.canvas.layout.camera {
                let cameraTrack = videoTracks[1]
                let camNatural = cameraTrack.naturalSize
                let camSourceSize = CoreFoundation.CGSize(
                    width: camNatural.width > 0 ? camNatural.width : 1280,
                    height: camNatural.height > 0 ? camNatural.height : 720
                )

                // Check if any segment has a per-segment camera override
                let hasPerSegmentCamera = project.timeline.segments.contains { $0.cameraPosition != nil }

                if hasPerSegmentCamera || defaultCamera.maskShape != .none {
                    // Use custom compositor with per-segment instructions
                    var maskedInstructions: [MaskedVideoCompositionInstruction] = []
                    let totalDuration = composition.duration
                    let overlayConfigs = project.overlays.map { OverlayConfig(overlay: $0) }

                    for (i, segment) in project.timeline.segments.enumerated() {
                        let segCamera = segment.cameraPosition ?? defaultCamera
                        let segCameraTransform = Self.cameraTransform(
                            position: segCamera, camSourceSize: camSourceSize, renderSize: renderSize
                        )

                        // Use previous instruction's end as start to guarantee contiguity
                        let segStart: CMTime
                        if let prev = maskedInstructions.last {
                            segStart = CMTimeRangeGetEnd(prev.timeRange)
                        } else {
                            segStart = .zero
                        }
                        // Last segment extends to composition end to avoid gaps
                        let segEnd: CMTime
                        if i == project.timeline.segments.count - 1 {
                            segEnd = totalDuration
                        } else {
                            segEnd = CMTime(seconds: segment.timelineIn + segment.timelineDuration, preferredTimescale: 600)
                        }
                        let segDuration = CMTimeSubtract(segEnd, segStart)

                        maskedInstructions.append(MaskedVideoCompositionInstruction(
                            timeRange: CMTimeRangeMake(start: segStart, duration: segDuration),
                            screenTrackID: screenTrack.trackID,
                            cameraTrackID: cameraTrack.trackID,
                            renderSize: renderSize,
                            screenTransform: screenTransform,
                            cameraTransform: segCameraTransform,
                            cameraRect: CGRect(x: segCamera.x, y: segCamera.y, width: segCamera.w, height: segCamera.h),
                            maskShape: segCamera.maskShape,
                            cornerRadius: CGFloat(segCamera.cornerRadius),
                            layoutType: layoutType,
                            videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                            videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                            padding: CGFloat(project.canvas.padding),
                            backgroundType: project.canvas.background.type,
                            backgroundValue: project.canvas.background.value,
                            cameraBorderWidth: CGFloat(segCamera.borderWidth),
                            cameraBorderColor: segCamera.borderColor,
                            overlays: overlayConfigs
                        ))
                    }

                    videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                    videoComposition.instructions = maskedInstructions
                    logger.debug("Built \(maskedInstructions.count) per-segment compositor instructions")
                    return videoComposition
                }

                // Standard PiP (no mask, no per-segment camera)
                let cameraTransform = Self.cameraTransform(
                    position: defaultCamera, camSourceSize: camSourceSize, renderSize: renderSize
                )
                let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
                cameraLayerInstruction.setTransform(cameraTransform, at: .zero)
                instruction.layerInstructions = [cameraLayerInstruction, screenLayerInstruction]

                // If there are overlays, use the custom compositor so they render during playback
                if !project.overlays.isEmpty {
                    let overlayConfigs = project.overlays.map { OverlayConfig(overlay: $0) }
                    let maskedInstruction = MaskedVideoCompositionInstruction(
                        timeRange: instruction.timeRange,
                        screenTrackID: screenTrack.trackID,
                        cameraTrackID: cameraTrack.trackID,
                        renderSize: renderSize,
                        screenTransform: screenTransform,
                        cameraTransform: cameraTransform,
                        cameraRect: nil,
                        maskShape: defaultCamera.maskShape,
                        cornerRadius: CGFloat(defaultCamera.cornerRadius),
                        layoutType: layoutType,
                        screenMuted: screenMuted,
                        videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                        videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                        padding: CGFloat(project.canvas.padding),
                        backgroundType: project.canvas.background.type,
                        backgroundValue: project.canvas.background.value,
                        cameraBorderWidth: CGFloat(defaultCamera.borderWidth),
                        cameraBorderColor: defaultCamera.borderColor,
                        overlays: overlayConfigs
                    )
                    videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                    videoComposition.instructions = [maskedInstruction]
                    return videoComposition
                }
            } else {
                instruction.layerInstructions = [screenLayerInstruction]

                // If there are overlays but no camera, use custom compositor
                if !project.overlays.isEmpty {
                    let overlayConfigs = project.overlays.map { OverlayConfig(overlay: $0) }
                    let maskedInstruction = MaskedVideoCompositionInstruction(
                        timeRange: instruction.timeRange,
                        screenTrackID: screenTrack.trackID,
                        cameraTrackID: nil,
                        renderSize: renderSize,
                        screenTransform: screenTransform,
                        cameraTransform: nil,
                        cameraRect: nil,
                        maskShape: .none,
                        cornerRadius: 0,
                        layoutType: layoutType,
                        screenMuted: screenMuted,
                        videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                        videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                        padding: CGFloat(project.canvas.padding),
                        backgroundType: project.canvas.background.type,
                        backgroundValue: project.canvas.background.value,
                        cameraBorderWidth: 0,
                        cameraBorderColor: "#FFFFFF",
                        overlays: overlayConfigs
                    )
                    videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                    videoComposition.instructions = [maskedInstruction]
                    return videoComposition
                }
            }
        }

        videoComposition.instructions = [instruction]
        return videoComposition
    }

    /// Compute camera transform from a CameraPosition
    static func cameraTransform(
        position: Project.Canvas.Layout.CameraPosition,
        camSourceSize: CGSize,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let cameraW = position.w * renderSize.width
        let cameraH = position.h * renderSize.height
        let camScale = min(cameraW / camSourceSize.width, cameraH / camSourceSize.height)
        let camScaledW = camSourceSize.width * camScale
        let camScaledH = camSourceSize.height * camScale
        let camX = position.x * renderSize.width + (cameraW - camScaledW) / 2
        let camYFlipped = (1.0 - position.y - position.h)
        let camY = camYFlipped * renderSize.height + (cameraH - camScaledH) / 2

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: camX, y: camY)
        transform = transform.scaledBy(x: camScale, y: camScale)
        return transform
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

        let primaryClipCount = project.timeline.primaryTrack?.clips.count ?? 0
        logger.debug("Creating player with edits - project: \(project.name), clips: \(primaryClipCount)")

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
                resolveSources: { [self] takeId in
                    self.resolveSources(for: takeId)
                }
            )
        } catch {
            logger.error("Failed to build composition: \(error.localizedDescription)")
            throw PreviewError.playbackFailed("Preview failed: \(error.localizedDescription)")
        }

        // Store result first so buildVideoComposition can access static clips
        self.compositionResult = result

        let composition = result.composition
        let videoComposition = buildVideoComposition(
            for: project,
            composition: composition,
            staticClips: result.staticClips
        )

        // Create player item
        nonisolated(unsafe) let unsafeComposition = composition
        nonisolated(unsafe) let unsafeVideoComposition = videoComposition
        let playerItem = await MainActor.run {
            let item = AVPlayerItem(asset: unsafeComposition)
            item.videoComposition = unsafeVideoComposition
            return item
        }
        player = AVPlayer(playerItem: playerItem)
        self.composition = composition
        self.videoCompositionConfig = videoComposition

        // Apply default audio mix (mic boost) on initial load
        if let currentItem = player?.currentItem {
            let defaultMix = AudioMixBuilder.buildAudioMix(
                compositionResult: result,
                muteState: AudioMixBuilder.TrackMuteState(),
                segments: project.timeline.segments
            )
            nonisolated(unsafe) let unsafeDefaultMix = defaultMix
            await MainActor.run {
                currentItem.audioMix = unsafeDefaultMix
            }
        }

        logger.debug("Player created successfully with composition")
    }

    /// Apply video track mutes by rebuilding the video composition
    public func applyVideoMutes(screenMuted: Bool, cameraMuted: Bool) async {
        var newMuted: Set<VideoTrackID> = []
        if screenMuted { newMuted.insert(.screen) }
        if cameraMuted { newMuted.insert(.camera) }

        guard newMuted != mutedVideoTracks else { return }
        mutedVideoTracks = newMuted

        guard let project = project,
              let player = player,
              let currentItem = player.currentItem,
              let composition = self.composition as? AVMutableComposition else {
            return
        }

        let videoComposition = buildVideoComposition(
            for: project,
            composition: composition,
            staticClips: compositionResult?.staticClips ?? []
        )
        self.videoCompositionConfig = videoComposition

        await MainActor.run {
            currentItem.videoComposition = videoComposition
        }
    }

    /// Apply audio mix to the current player item for per-track mute/volume
    public func applyAudioMix(_ muteState: AudioMixBuilder.TrackMuteState) async {
        guard let compositionResult = compositionResult,
              let currentItem = player?.currentItem else { return }

        lastAudioMuteState = muteState

        let audioMix = AudioMixBuilder.buildAudioMix(
            compositionResult: compositionResult,
            muteState: muteState,
            segments: project?.timeline.segments ?? []
        )

        nonisolated(unsafe) let unsafeAudioMix = audioMix
        await MainActor.run {
            currentItem.audioMix = unsafeAudioMix
        }
    }
}
