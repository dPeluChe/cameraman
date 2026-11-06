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
        staticClips: [CompositionBuilder.StaticClipInfo] = [],
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        // Imported-video overlay tracks render via the custom compositor, so any
        // path below that would otherwise use standard layer instructions must
        // switch to MaskedVideoCompositor when videoOverlays exist.
        // Subtitle visibility toggle (the Subtitles track "eye"): when hidden,
        // exclude subtitles from what the compositor draws.
        let subtitlesHidden = mutedVideoTracks.contains(.subtitle)
        let activeOverlayConfigs: [OverlayConfig] = subtitlesHidden
            ? project.overlays.map { OverlayConfig(overlay: $0) }
            : project.overlayConfigs

        let needsCompositor = !project.overlays.isEmpty
            || (!subtitlesHidden && !project.subtitles.isEmpty)
            || !videoOverlays.isEmpty
            || project.hasMixedScreenResolutions || project.hasVisualAdjustments || project.hasCameraEffects
            || (project.syntheticCursor?.enabled == true && cursorPlan != nil)

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

        // Empty primary track (no recording): never reference it as a source.
        let screenTrackID = screenTrack.segments.isEmpty ? kCMPersistentTrackID_Invalid : screenTrack.trackID

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
            let overlayConfigs = activeOverlayConfigs

            // Use the custom compositor when a mask is set OR when there are
            // overlays/subtitles to draw — otherwise standard layer instructions
            // skip the overlay pass and captions never render (camera-fullscreen,
            // no-mask case).
            if maskShape != .none || needsCompositor {
                let maskedInstruction = MaskedVideoCompositionInstruction(
                    timeRange: CMTimeRangeMake(start: .zero, duration: composition.duration),
                    screenTrackID: screenTrackID,
                    cameraTrackID: cameraTrack.trackID,
                    renderSize: renderSize,
                    screenTransform: CGAffineTransform.identity,
                    cameraTransform: cameraTransform,
                    cameraRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    maskShape: maskShape,
                    cornerRadius: CGFloat(cornerRadius),
                    layoutType: "fullscreenCamera",
                    screenMuted: true,
                    overlays: overlayConfigs,
                    adjustments: project.adjustmentConfigs,
                    zoomPlan: self.zoomPlan,
                    videoOverlays: videoOverlays,
                    cursorPlan: self.cursorPlan,
                    cursorConfig: project.syntheticCursor,
                    cameraLayer: .preview(project, projectDirectory: projectDirectoryURL)
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

        // Side-by-side takes a column only while there is a camera to fill the other one.
        let cameraShown = hasCameraTrack && !cameraMuted
        let screenFrame = cameraShown ? project.canvas.layout.screenColumn(in: renderSize) : nil
        let screenTransform = Project.Canvas.Layout.fit(
            screenSourceSize, into: screenFrame ?? CGRect(origin: .zero, size: renderSize)
        )
        screenLayerInstruction.setTransform(screenTransform, at: .zero)

        // PiP camera overlay (skip if camera is muted)
        if cameraShown, let defaultCamera = project.canvas.layout.camera {
            let cameraTrack = videoTracks[1]
            let camNatural = cameraTrack.naturalSize
            let camSourceSize = CoreFoundation.CGSize(
                width: camNatural.width > 0 ? camNatural.width : 1280,
                height: camNatural.height > 0 ? camNatural.height : 720
            )

            // Check if any clip in primary track has a per-clip camera override
            let primaryClips = project.timeline.primaryTrack?.clips ?? []
            let hasPerClipCamera = primaryClips.contains { clip in
                if case .recording(let ref) = clip.content { return ref.cameraPosition != nil }
                return false
            }

            if hasPerClipCamera || defaultCamera.maskShape != .none || project.hasCameraEffects {
                // Use custom compositor with per-clip instructions
                var maskedInstructions: [MaskedVideoCompositionInstruction] = []
                let totalDuration = composition.duration
                let overlayConfigs = activeOverlayConfigs

                for (i, clip) in primaryClips.enumerated() {
                    // For non-recording clips, use default camera
                    let clipCamera: Project.Canvas.Layout.CameraPosition
                    if case .recording(let ref) = clip.content {
                        clipCamera = ref.cameraPosition ?? defaultCamera
                    } else {
                        clipCamera = defaultCamera
                    }
                    let clipCameraTransform = Self.cameraTransform(
                        position: clipCamera, camSourceSize: camSourceSize, renderSize: renderSize
                    )

                    // Use previous instruction's end as start to guarantee contiguity
                    let segStart: CMTime
                    if let prev = maskedInstructions.last {
                        segStart = CMTimeRangeGetEnd(prev.timeRange)
                    } else {
                        segStart = .zero
                    }
                    // Last clip extends to composition end to avoid gaps
                    let segEnd: CMTime
                    if i == primaryClips.count - 1 {
                        segEnd = totalDuration
                    } else {
                        segEnd = CMTime(seconds: clip.timelineOut, preferredTimescale: 600)
                    }
                    let segDuration = CMTimeSubtract(segEnd, segStart)

                    maskedInstructions.append(MaskedVideoCompositionInstruction(
                        timeRange: CMTimeRangeMake(start: segStart, duration: segDuration),
                        screenTrackID: screenTrackID,
                        cameraTrackID: cameraTrack.trackID,
                        renderSize: renderSize,
                        screenTransform: screenTransform,
                        screenFrame: screenFrame,
                        cameraTransform: clipCameraTransform,
                        cameraRect: CGRect(x: clipCamera.x, y: clipCamera.y, width: clipCamera.w, height: clipCamera.h),
                        maskShape: clipCamera.maskShape,
                        cornerRadius: CGFloat(clipCamera.cornerRadius),
                        layoutType: layoutType,
                        videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
                        videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
                        padding: CGFloat(project.canvas.padding),
                        backgroundType: project.canvas.background.type,
                        backgroundValue: project.canvas.background.value,
                        cameraBorderWidth: CGFloat(clipCamera.borderWidth),
                        cameraBorderColor: clipCamera.borderColor,
                        overlays: overlayConfigs,
                        adjustments: project.adjustmentConfigs,
                        zoomPlan: self.zoomPlan,
                        videoOverlays: videoOverlays,
                        cursorPlan: self.cursorPlan,
                        cursorConfig: project.syntheticCursor,
                        cameraLayer: .preview(project, projectDirectory: projectDirectoryURL)
                    ))
                }

                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = maskedInstructions
                // Note: no log here — buildVideoComposition runs on every PiP drag
                // tick during live preview and floods the console (hundreds of
                // identical entries per second). Export side has its own log.
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
            if needsCompositor {
                let overlayConfigs = activeOverlayConfigs
                let maskedInstruction = MaskedVideoCompositionInstruction(
                    timeRange: instruction.timeRange,
                    screenTrackID: screenTrackID,
                    cameraTrackID: cameraTrack.trackID,
                    renderSize: renderSize,
                    screenTransform: screenTransform,
                    screenFrame: screenFrame,
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
                    overlays: overlayConfigs,
                    adjustments: project.adjustmentConfigs,
                    zoomPlan: self.zoomPlan,
                    videoOverlays: videoOverlays,
                    cursorPlan: self.cursorPlan,
                    cursorConfig: project.syntheticCursor,
                    cameraLayer: .preview(project, projectDirectory: projectDirectoryURL)
                )
                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = [maskedInstruction]
                return videoComposition
            }
        } else {
            instruction.layerInstructions = [screenLayerInstruction]

            // If there are overlays but no camera, use custom compositor
            if needsCompositor {
                let overlayConfigs = activeOverlayConfigs
                let maskedInstruction = MaskedVideoCompositionInstruction(
                    timeRange: instruction.timeRange,
                    screenTrackID: screenTrackID,
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
                    overlays: overlayConfigs,
                    adjustments: project.adjustmentConfigs,
                    zoomPlan: self.zoomPlan,
                    videoOverlays: videoOverlays,
                    cursorPlan: self.cursorPlan,
                    cursorConfig: project.syntheticCursor,
                    cameraLayer: .preview(project, projectDirectory: projectDirectoryURL)
                )
                videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
                videoComposition.instructions = [maskedInstruction]
                return videoComposition
            }
        }
        // If there are static clips (image/color), delegate to extension
        if !staticClips.isEmpty {
            let allInstructions = buildStaticClipInstructions(
                project: project,
                composition: composition,
                staticClips: staticClips,
                renderSize: renderSize,
                baseInstruction: instruction,
                videoOverlays: videoOverlays
            )
            videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
            videoComposition.instructions = allInstructions
            return videoComposition
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

}
