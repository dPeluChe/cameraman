//
//  CompositionBuilder+AudioTracks.swift
//  EngineKit
//
//  Audio track building: recording audio, imported media items, and timeline audio clips.
//

import Foundation
import AVFoundation

extension CompositionBuilder {

    // MARK: - Recording Audio Track

    func buildRecordingAudioTrack(
        into composition: AVMutableComposition,
        clips: [Project.TimelineClip],
        audioPath: String?,
        trackLabel: String,
        resolver: SourceResolver,
        resolveSources: SourcesForTake,
        cancellationCheck: CancellationCheck?
    ) async throws -> AVMutableCompositionTrack? {
        guard let audioPath = audioPath else {
            logger.debug("No \(trackLabel) track available")
            return nil
        }

        let audioURL = resolver.projectDirectory.appendingPathComponent(audioPath)

        guard fileManager.fileExists(atPath: audioURL.path) else {
            logger.warning("\(trackLabel) file not found: \(audioURL.path)")
            return nil
        }

        let audioAsset = AVAsset(url: audioURL)
        let audioAssetTracks: [AVAssetTrack]
        do {
            audioAssetTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        } catch {
            logger.warning("Failed to load \(trackLabel) tracks: \(error.localizedDescription)")
            return nil
        }

        guard let sourceAudioTrack = audioAssetTracks.first else {
            logger.debug("No audio data found in \(trackLabel) source")
            return nil
        }

        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            logger.warning("Failed to create \(trackLabel) track in composition")
            return nil
        }

        var currentTime = CMTime.zero

        for clip in clips {
            try await cancellationCheck?()

            guard case .recording(let ref) = clip.content else {
                let gapDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
                currentTime = CMTimeAdd(currentTime, gapDuration)
                continue
            }

            let startTime = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
            let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

            do {
                try audioTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceAudioTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: audioTrack, at: currentTime, duration: duration, speed: clip.speed
                )

                currentTime = CMTimeAdd(currentTime, effectiveDuration)
            } catch {
                logger.error("Failed to insert audio at \(ref.sourceIn)s: \(error.localizedDescription)")
                let gapDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / clip.speed)
                currentTime = CMTimeAdd(currentTime, gapDuration)
            }
        }

        logger.debug("\(trackLabel) track built successfully")
        return audioTrack
    }

    // MARK: - Additional Audio Tracks (Legacy Imported Media)

    func buildAdditionalAudioTracks(
        into composition: AVMutableComposition,
        mediaItems: [Project.MediaItem],
        resolver: SourceResolver
    ) async -> [(track: AVMutableCompositionTrack, mediaItem: Project.MediaItem)] {
        var result: [(track: AVMutableCompositionTrack, mediaItem: Project.MediaItem)] = []

        for item in mediaItems {
            let audioURL = resolver.projectDirectory.appendingPathComponent(item.path)

            guard fileManager.fileExists(atPath: audioURL.path) else {
                logger.warning("Additional audio file not found: \(audioURL.path)")
                continue
            }

            let audioAsset = AVAsset(url: audioURL)

            do {
                let audioAssetTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                guard let sourceTrack = audioAssetTracks.first else {
                    logger.warning("No audio data in imported file: \(item.name)")
                    continue
                }

                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    logger.warning("Failed to create composition track for: \(item.name)")
                    continue
                }

                let insertTime = CMTime(seconds: item.timelineIn, preferredTimescale: 600)
                let duration = CMTime(seconds: item.duration, preferredTimescale: 600)

                try compositionTrack.insertTimeRange(
                    CMTimeRangeMake(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: insertTime
                )

                logger.debug("Additional audio '\(item.name)' inserted at \(item.timelineIn)s, duration \(item.duration)s")
                result.append((track: compositionTrack, mediaItem: item))
            } catch {
                logger.error("Failed to insert additional audio '\(item.name)': \(error.localizedDescription)")
            }
        }

        return result
    }

    // MARK: - Audio Clip Tracks (from timeline audio tracks)

    func buildAudioClipTracks(
        into composition: AVMutableComposition,
        tracks: [Project.TimelineTrack],
        resolver: SourceResolver
    ) async -> [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] {
        var result: [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] = []

        for track in tracks where !track.isMuted {
            for clip in track.clips {
                guard case .audio(let ref) = clip.content else { continue }

                let audioURL = resolver.projectDirectory.appendingPathComponent(ref.path)
                guard fileManager.fileExists(atPath: audioURL.path) else {
                    logger.warning("Audio clip file not found: \(audioURL.path)")
                    continue
                }

                let audioAsset = AVAsset(url: audioURL)

                do {
                    let audioAssetTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                    guard let sourceTrack = audioAssetTracks.first else {
                        logger.warning("No audio data in clip: \(clip.id)")
                        continue
                    }

                    guard let compositionTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                        logger.warning("Failed to create audio clip track for: \(clip.id)")
                        continue
                    }

                    let insertTime = CMTime(seconds: clip.timelineIn, preferredTimescale: 600)
                    let sourceStart = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                    let duration = CMTime(seconds: ref.duration, preferredTimescale: 600)

                    try compositionTrack.insertTimeRange(
                        CMTimeRangeMake(start: sourceStart, duration: duration),
                        of: sourceTrack,
                        at: insertTime
                    )

                    if clip.speed != 1.0 {
                        applySpeedIfNeeded(
                            to: compositionTrack, at: insertTime, duration: duration, speed: clip.speed
                        )
                    }

                    logger.debug("Audio clip '\(clip.id)' inserted at \(clip.timelineIn)s")
                    result.append((track: compositionTrack, clip: clip))
                } catch {
                    logger.error("Failed to insert audio clip '\(clip.id)': \(error.localizedDescription)")
                }
            }
        }

        return result
    }
}
