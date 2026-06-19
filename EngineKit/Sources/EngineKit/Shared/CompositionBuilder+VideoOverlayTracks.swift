//
//  CompositionBuilder+VideoOverlayTracks.swift
//  EngineKit
//
//  Imported-video overlay tracks: video frames as extra composition tracks
//  (composited like the camera track) and their embedded audio as audio
//  composition tracks (mirroring buildAudioClipTracks).
//

import Foundation
import AVFoundation

extension CompositionBuilder.Result {
    /// Compositor-ready sources for the imported-video overlay tracks, including
    /// each clip's timeline window and canvas placement (PiP position).
    public var videoOverlaySources: [MaskedVideoCompositionInstruction.VideoOverlaySource] {
        videoOverlayTracks.map { info in
            let windows = info.timelineTrack.clips.compactMap { clip -> MaskedVideoCompositionInstruction.VideoOverlaySource.ClipWindow? in
                guard case .video = clip.content else { return nil }
                let rect = clip.position.map {
                    CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)
                }
                // Visual effects on this imported clip, flattened to absolute time.
                return .init(start: clip.timelineIn, end: clip.timelineOut, position: rect, adjustments: clip.visualAdjustmentConfigs())
            }
            return MaskedVideoCompositionInstruction.VideoOverlaySource(
                trackID: info.track.trackID,
                opacity: info.timelineTrack.opacity,
                clipWindows: windows
            )
        }
    }
}

extension CompositionBuilder {

    /// A built overlay video track: the AVComposition track plus the timeline
    /// track it came from (for opacity/mute) — used by the compositor.
    public struct VideoOverlayTrackInfo {
        public let track: AVMutableCompositionTrack
        public let timelineTrack: Project.TimelineTrack
    }

    // MARK: - Video frames (overlay tracks)

    /// Build one AVComposition video track per timeline `.video` track. Unlike the
    /// primary track (sequential), overlay clips are inserted AT their timelineIn,
    /// leaving gaps empty — the compositor only composites where frames exist.
    func buildVideoOverlayTracks(
        into composition: AVMutableComposition,
        tracks: [Project.TimelineTrack],
        resolver: SourceResolver,
        cancellationCheck: CancellationCheck?
    ) async throws -> [VideoOverlayTrackInfo] {
        var result: [VideoOverlayTrackInfo] = []

        for timelineTrack in tracks where !timelineTrack.isMuted {
            let videoClips = timelineTrack.clips.filter {
                if case .video = $0.content { return true }
                return false
            }
            guard !videoClips.isEmpty else { continue }

            guard let overlayTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                logger.warning("Failed to create overlay video track for \(timelineTrack.name)")
                continue
            }

            for clip in videoClips {
                try await cancellationCheck?()
                guard case .video(let ref) = clip.content else { continue }

                let videoURL = resolver.projectDirectory.appendingPathComponent(ref.path)
                guard fileManager.fileExists(atPath: videoURL.path) else {
                    logger.warning("Overlay video not found: \(videoURL.path)")
                    continue
                }

                do {
                    let asset = AVAsset(url: videoURL)
                    let videoAssetTracks = try await asset.loadTracks(withMediaType: .video)
                    guard let sourceTrack = videoAssetTracks.first else {
                        logger.warning("No video track in overlay clip: \(ref.path)")
                        continue
                    }

                    let insertTime = CMTime(seconds: clip.timelineIn, preferredTimescale: 600)
                    let sourceStart = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                    let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

                    try overlayTrack.insertTimeRange(
                        CMTimeRangeMake(start: sourceStart, duration: duration),
                        of: sourceTrack,
                        at: insertTime
                    )

                    if clip.speed != 1.0 {
                        applySpeedIfNeeded(
                            to: overlayTrack, at: insertTime, duration: duration, speed: clip.speed
                        )
                    }

                    logger.debug("Overlay video clip '\(clip.id)' inserted at \(clip.timelineIn)s")
                } catch {
                    logger.error("Failed to insert overlay video clip '\(clip.id)': \(error.localizedDescription)")
                }
            }

            result.append(VideoOverlayTrackInfo(track: overlayTrack, timelineTrack: timelineTrack))
        }

        return result
    }

    // MARK: - Embedded audio from video clips

    /// Extract the embedded audio of every `.video` clip on `.video` timeline tracks
    /// into its own audio composition track (same shape as buildAudioClipTracks),
    /// so imported footage plays and exports WITH its sound.
    func buildVideoClipAudioTracks(
        into composition: AVMutableComposition,
        tracks: [Project.TimelineTrack],
        resolver: SourceResolver
    ) async -> [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] {
        var result: [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] = []

        for track in tracks where !track.isMuted {
            for clip in track.clips {
                guard case .video(let ref) = clip.content else { continue }

                let videoURL = resolver.projectDirectory.appendingPathComponent(ref.path)
                guard fileManager.fileExists(atPath: videoURL.path) else { continue }

                let asset = AVAsset(url: videoURL)

                do {
                    let audioAssetTracks = try await asset.loadTracks(withMediaType: .audio)
                    guard let sourceAudioTrack = audioAssetTracks.first else {
                        logger.debug("Video clip '\(clip.id)' has no embedded audio")
                        continue
                    }

                    guard let compositionTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                        logger.warning("Failed to create audio track for video clip: \(clip.id)")
                        continue
                    }

                    let insertTime = CMTime(seconds: clip.timelineIn, preferredTimescale: 600)
                    let sourceStart = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                    let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

                    try compositionTrack.insertTimeRange(
                        CMTimeRangeMake(start: sourceStart, duration: duration),
                        of: sourceAudioTrack,
                        at: insertTime
                    )

                    if clip.speed != 1.0 {
                        applySpeedIfNeeded(
                            to: compositionTrack, at: insertTime, duration: duration, speed: clip.speed
                        )
                    }

                    logger.debug("Video clip audio '\(clip.id)' inserted at \(clip.timelineIn)s")
                    result.append((track: compositionTrack, clip: clip))
                } catch {
                    logger.error("Failed to extract audio from video clip '\(clip.id)': \(error.localizedDescription)")
                }
            }
        }

        return result
    }
}
