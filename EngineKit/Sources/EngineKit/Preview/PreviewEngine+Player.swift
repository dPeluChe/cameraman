//
//  PreviewEngine+Player.swift
//  EngineKit
//
//  AVPlayer creation, audio/video mute application, and source resolution.
//  Extracted from PreviewComposition.swift.
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

        // Empty projects (no recording) are valid: imported clips on overlay
        // tracks still build a playable composition.

        guard let projectDir = projectDirectory else {
            throw PreviewError.playbackFailed("No project directory set")
        }

        let primaryClipCount = project.timeline.primaryTrack?.clips.count ?? 0
        logger.debug("Creating player with edits - project: \(project.name), clips: \(primaryClipCount)")

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

        self.compositionResult = result

        let composition = result.composition
        let videoComposition = buildVideoComposition(
            for: project,
            composition: composition,
            staticClips: result.staticClips,
            videoOverlays: result.videoOverlaySources
        )

        nonisolated(unsafe) let unsafeComposition = composition
        let unsafeVideoComposition = videoComposition
        let playerItem = await MainActor.run {
            let item = AVPlayerItem(asset: unsafeComposition)
            // A zero-duration composition (empty project before any import) can't
            // carry a videoComposition — its lone instruction would have an empty
            // time range, which AVFoundation rejects as invalid.
            if unsafeComposition.duration.seconds > 0 {
                item.videoComposition = unsafeVideoComposition
            }
            return item
        }
        player = AVPlayer(playerItem: playerItem)
        self.composition = composition
        self.videoCompositionConfig = videoComposition

        if let currentItem = player?.currentItem {
            let defaultMix = AudioMixBuilder.buildAudioMix(
                compositionResult: result,
                muteState: AudioMixBuilder.TrackMuteState(),
                segments: project.timeline.segments,
                audioAdjustments: project.audioAdjustmentSpecs
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
            staticClips: compositionResult?.staticClips ?? [],
            videoOverlays: compositionResult?.videoOverlaySources ?? []
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
            segments: project?.timeline.segments ?? [],
            audioAdjustments: project?.audioAdjustmentSpecs ?? []
        )

        nonisolated(unsafe) let unsafeAudioMix = audioMix
        await MainActor.run {
            currentItem.audioMix = unsafeAudioMix
        }
    }
}
