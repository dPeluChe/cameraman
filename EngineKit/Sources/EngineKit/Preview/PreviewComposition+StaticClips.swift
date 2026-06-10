//
//  PreviewComposition+StaticClips.swift
//  EngineKit
//
//  Handles building video composition instructions for static clips
//  (images, colors) interspersed with video content.
//

import Foundation
import AVFoundation

extension PreviewEngine {

    /// Build video composition instructions that interleave normal video
    /// with static content (image/color clips) using the custom compositor.
    func buildStaticClipInstructions(
        project: Project,
        composition: AVComposition,
        staticClips: [CompositionBuilder.StaticClipInfo],
        renderSize: CGSize,
        baseInstruction: AVMutableVideoCompositionInstruction,
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) -> [AVVideoCompositionInstructionProtocol] {
        let screenTrack = composition.tracks(withMediaType: .video).first
        let overlayConfigs = project.overlayConfigs
        var allInstructions: [AVVideoCompositionInstructionProtocol] = []

        let totalDuration = composition.duration
        var coveredEnd = CMTime.zero

        for info in staticClips {
            let staticStart = info.timeRange.start
            let staticEnd = CMTimeAdd(info.timeRange.start, info.timeRange.duration)

            // Gap before this static clip: normal video
            if CMTimeCompare(coveredEnd, staticStart) < 0 {
                let gapRange = CMTimeRangeMake(start: coveredEnd, duration: CMTimeSubtract(staticStart, coveredEnd))
                if let screenTrackID = screenTrack?.trackID {
                    allInstructions.append(makeNormalInstruction(
                        timeRange: gapRange,
                        screenTrackID: screenTrackID,
                        renderSize: renderSize,
                        project: project,
                        overlays: overlayConfigs,
                        videoOverlays: videoOverlays
                    ))
                }
            }

            // Static clip instruction
            let staticContent: MaskedVideoCompositionInstruction.StaticClipContent
            switch info.clip.content {
            case .image(let ref):
                let projectDir = self.projectDirectory ?? ""
                let fullPath = URL(fileURLWithPath: projectDir).appendingPathComponent(ref.path).path
                staticContent = .image(path: fullPath)
            case .color(let ref):
                staticContent = .color(hexColor: ref.hexColor)
            default:
                coveredEnd = staticEnd
                continue
            }

            // Static clips (image/color) intentionally do not receive a zoom plan
            // — they have no source video to zoom into.
            let staticInstruction = MaskedVideoCompositionInstruction(
                timeRange: info.timeRange,
                screenTrackID: screenTrack?.trackID ?? 1,
                cameraTrackID: nil,
                renderSize: renderSize,
                screenTransform: .identity,
                cameraTransform: nil,
                cameraRect: nil,
                maskShape: .none,
                cornerRadius: 0,
                layoutType: "static",
                backgroundType: project.canvas.background.type,
                backgroundValue: project.canvas.background.value,
                overlays: overlayConfigs,
                staticContent: staticContent,
                videoOverlays: videoOverlays
            )
            allInstructions.append(staticInstruction)
            coveredEnd = staticEnd
        }

        // Remaining time after last static clip
        if CMTimeCompare(coveredEnd, totalDuration) < 0 {
            let remainingRange = CMTimeRangeMake(start: coveredEnd, duration: CMTimeSubtract(totalDuration, coveredEnd))
            if let screenTrackID = screenTrack?.trackID {
                allInstructions.append(makeNormalInstruction(
                    timeRange: remainingRange,
                    screenTrackID: screenTrackID,
                    renderSize: renderSize,
                    project: project,
                    overlays: overlayConfigs
                ))
            }
        }

        return allInstructions
    }

    private func makeNormalInstruction(
        timeRange: CMTimeRange,
        screenTrackID: CMPersistentTrackID,
        renderSize: CGSize,
        project: Project,
        overlays: [OverlayConfig],
        videoOverlays: [MaskedVideoCompositionInstruction.VideoOverlaySource] = []
    ) -> MaskedVideoCompositionInstruction {
        MaskedVideoCompositionInstruction(
            timeRange: timeRange,
            screenTrackID: screenTrackID,
            cameraTrackID: nil,
            renderSize: renderSize,
            screenTransform: .identity,
            cameraTransform: nil,
            cameraRect: nil,
            maskShape: .none,
            cornerRadius: 0,
            layoutType: project.canvas.layout.type,
            videoCornerRadius: CGFloat(project.canvas.videoCornerRadius),
            videoShadowIntensity: CGFloat(project.canvas.videoShadowIntensity),
            padding: CGFloat(project.canvas.padding),
            backgroundType: project.canvas.background.type,
            backgroundValue: project.canvas.background.value,
            overlays: overlays,
            zoomPlan: self.zoomPlan,
            videoOverlays: videoOverlays
        )
    }
}
