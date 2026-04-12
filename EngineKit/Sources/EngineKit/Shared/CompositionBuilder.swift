//
//  CompositionBuilder.swift
//  EngineKit
//
//  Shared composition building logic for Preview and Export.
//  Eliminates duplication of segment insertion, speed scaling,
//  and multi-track composition between the two pipelines.
//
//  Updated for multi-track timeline: builds composition from tracks/clips,
//  handling recording clips, imported video, audio, and static content.
//

import Foundation
import AVFoundation
import os.log

/// Builds an AVMutableComposition from project timeline tracks.
/// Used by both PreviewEngine and ExportEngine to ensure identical
/// timeline behavior (cuts, trims, speed changes) across preview and export.
public struct CompositionBuilder {

    private let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "CompositionBuilder")
    private let fileManager: FileManager

    /// Result of building a composition
    public struct Result {
        /// The built composition with all tracks
        public let composition: AVMutableComposition
        /// The video track (screen)
        public let videoTrack: AVMutableCompositionTrack
        /// The camera track (nil if no camera)
        public let cameraTrack: AVMutableCompositionTrack?
        /// System audio track (nil if no system audio)
        public let systemAudioTrack: AVMutableCompositionTrack?
        /// Microphone audio track (nil if no mic audio)
        public let micAudioTrack: AVMutableCompositionTrack?
        /// Additional audio tracks from imported media items
        public let additionalAudioTracks: [(track: AVMutableCompositionTrack, mediaItem: Project.MediaItem)]
        /// Additional audio tracks from audio clips in tracks
        public let audioClipTracks: [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)]
        /// Non-recording clips in the primary track (image, color, video) with their timeline positions.
        /// The compositor uses this to render static content where the video track has gaps.
        public let staticClips: [StaticClipInfo]
    }

    /// Info about a non-recording clip that the compositor needs to render
    public struct StaticClipInfo: Sendable {
        public let clip: Project.TimelineClip
        public let timeRange: CMTimeRange
    }

    /// Configuration for how to resolve source file paths
    public struct SourceResolver {
        /// Base directory for resolving relative paths
        public let projectDirectory: URL
        /// Optional proxy path for screen (absolute path, nil = use original)
        public let screenProxyPath: String?
        /// Optional proxy path for camera (absolute path, nil = use original)
        public let cameraProxyPath: String?

        public init(
            projectDirectory: URL,
            screenProxyPath: String? = nil,
            cameraProxyPath: String? = nil
        ) {
            self.projectDirectory = projectDirectory
            self.screenProxyPath = screenProxyPath
            self.cameraProxyPath = cameraProxyPath
        }
    }

    /// Callback for resolving sources by take ID
    public typealias SourcesForTake = (UUID?) -> Project.Sources?

    /// Legacy callback type — takes a segment, extracts takeId
    public typealias SourcesForSegment = (Project.Timeline.Segment) -> Project.Sources?

    /// Optional cancellation check — throw to cancel
    public typealias CancellationCheck = () async throws -> Void

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Build a full composition from project timeline tracks
    public func buildComposition(
        project: Project,
        resolver: SourceResolver,
        resolveSources: @escaping SourcesForTake,
        cancellationCheck: CancellationCheck? = nil
    ) async throws -> Result {
        let composition = AVMutableComposition()
        var assetCache: [String: AVAsset] = [:]

        // Get primary track clips (all clips, not just recording)
        let primaryClips = project.timeline.primaryTrack?.clips ?? []
        // Extract recording clips for video/camera/audio track building
        let recordingClips = primaryClips.filter { $0.isRecording }

        // 1. Build video (screen) track — handles recording clips,
        //    inserts gaps for non-recording clips (compositor renders them)
        let (videoTrack, staticClips) = try await buildPrimaryVideoTrack(
            into: composition,
            clips: primaryClips,
            resolver: resolver,
            resolveSources: resolveSources,
            assetCache: &assetCache,
            cancellationCheck: cancellationCheck
        )

        // 2. Build camera track (if available) — only from recording clips
        let cameraTrack = try await buildCameraTrack(
            into: composition,
            clips: recordingClips,
            allClips: primaryClips,
            resolver: resolver,
            resolveSources: resolveSources,
            assetCache: &assetCache,
            cancellationCheck: cancellationCheck
        )

        // 3. Build system audio track (if available)
        let systemAudioTrack = try await buildRecordingAudioTrack(
            into: composition,
            clips: primaryClips,
            audioPath: project.primarySources?.audio?.system?.path,
            trackLabel: "system audio",
            resolver: resolver,
            resolveSources: resolveSources,
            cancellationCheck: cancellationCheck
        )

        // 4. Build mic audio track (if available)
        let micAudioTrack = try await buildRecordingAudioTrack(
            into: composition,
            clips: primaryClips,
            audioPath: project.primarySources?.audio?.mic?.path,
            trackLabel: "mic audio",
            resolver: resolver,
            resolveSources: resolveSources,
            cancellationCheck: cancellationCheck
        )

        // 5. Build additional audio tracks from legacy imported media items
        let additionalAudioTracks = await buildAdditionalAudioTracks(
            into: composition,
            mediaItems: project.mediaItems.filter { $0.type == .audio && !$0.isMuted },
            resolver: resolver
        )

        // 6. Build audio tracks from audio clips in timeline tracks
        let audioClipTracks = await buildAudioClipTracks(
            into: composition,
            tracks: project.timeline.audioTracks,
            resolver: resolver
        )

        return Result(
            composition: composition,
            videoTrack: videoTrack,
            cameraTrack: cameraTrack,
            systemAudioTrack: systemAudioTrack,
            micAudioTrack: micAudioTrack,
            additionalAudioTracks: additionalAudioTracks,
            audioClipTracks: audioClipTracks,
            staticClips: staticClips
        )
    }

    /// Legacy overload accepting SourcesForSegment callback
    public func buildComposition(
        project: Project,
        resolver: SourceResolver,
        resolveSources: @escaping SourcesForSegment,
        cancellationCheck: CancellationCheck? = nil
    ) async throws -> Result {
        // Convert segment-based callback to take-based callback
        let takeCallback: SourcesForTake = { takeId in
            let dummySegment = Project.Timeline.Segment(
                takeId: takeId,
                sourceIn: 0,
                sourceOut: 0,
                timelineIn: 0
            )
            return resolveSources(dummySegment)
        }
        return try await buildComposition(
            project: project,
            resolver: resolver,
            resolveSources: takeCallback,
            cancellationCheck: cancellationCheck
        )
    }

    // MARK: - Primary Video Track

    /// Build the primary video track from all clips (recording clips get video,
    /// non-recording clips create gaps that the compositor fills)
    private func buildPrimaryVideoTrack(
        into composition: AVMutableComposition,
        clips: [Project.TimelineClip],
        resolver: SourceResolver,
        resolveSources: SourcesForTake,
        assetCache: inout [String: AVAsset],
        cancellationCheck: CancellationCheck?
    ) async throws -> (AVMutableCompositionTrack, [StaticClipInfo]) {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompositionBuilderError.failedToCreateTrack("video")
        }

        var currentTime = CMTime.zero
        var staticClips: [StaticClipInfo] = []

        for (index, clip) in clips.enumerated() {
            try await cancellationCheck?()

            switch clip.content {
            case .recording(let ref):
                // Insert actual video from source
                guard let sources = resolveSources(ref.takeId) else {
                    logger.warning("No sources for recording clip \(clip.id), skipping")
                    continue
                }

                let asset = try await resolveAsset(
                    path: sources.screen.path,
                    proxyPath: resolver.screenProxyPath,
                    resolver: resolver,
                    cache: &assetCache
                )

                let videoAssetTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceTrack = videoAssetTracks.first else {
                    logger.warning("No video track in source for clip \(clip.id), skipping")
                    continue
                }

                let startTime = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

                try videoTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: videoTrack, at: currentTime, duration: duration, speed: clip.speed
                )

                logger.debug("Video recording clip \(index + 1): \(ref.sourceIn)s-\(ref.sourceOut)s, speed \(clip.speed)x")
                currentTime = CMTimeAdd(currentTime, effectiveDuration)

            case .video(let ref):
                // Insert imported video
                let videoURL = resolver.projectDirectory.appendingPathComponent(ref.path)
                guard fileManager.fileExists(atPath: videoURL.path) else {
                    logger.warning("Imported video not found: \(videoURL.path)")
                    let gapDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
                    currentTime = CMTimeAdd(currentTime, gapDuration)
                    continue
                }

                let asset = AVAsset(url: videoURL)
                let videoAssetTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceTrack = videoAssetTracks.first else {
                    logger.warning("No video track in imported video: \(ref.path)")
                    let gapDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
                    currentTime = CMTimeAdd(currentTime, gapDuration)
                    continue
                }

                let startTime = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

                try videoTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: videoTrack, at: currentTime, duration: duration, speed: clip.speed
                )

                logger.debug("Video import clip \(index + 1): \(ref.sourceIn)s-\(ref.sourceOut)s")
                currentTime = CMTimeAdd(currentTime, effectiveDuration)

            case .image, .color:
                // Insert gap — compositor will render the image/color for this time range
                let gapDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
                let timeRange = CMTimeRangeMake(start: currentTime, duration: gapDuration)

                try videoTrack.insertEmptyTimeRange(timeRange)

                staticClips.append(StaticClipInfo(clip: clip, timeRange: timeRange))

                logger.debug("Static clip \(index + 1): \(clip.duration)s at \(currentTime.seconds)s")
                currentTime = CMTimeAdd(currentTime, gapDuration)

            case .audio:
                // Audio clips don't belong in the primary video track, skip
                logger.debug("Skipping audio clip in primary track: \(clip.id)")
                continue
            }
        }

        return (videoTrack, staticClips)
    }

    // MARK: - Camera Track

    private func buildCameraTrack(
        into composition: AVMutableComposition,
        clips: [Project.TimelineClip],
        allClips: [Project.TimelineClip],
        resolver: SourceResolver,
        resolveSources: SourcesForTake,
        assetCache: inout [String: AVAsset],
        cancellationCheck: CancellationCheck?
    ) async throws -> AVMutableCompositionTrack? {
        // Check if any recording clip has camera
        let hasCamera = clips.contains { clip in
            guard case .recording(let ref) = clip.content else { return false }
            return resolveSources(ref.takeId)?.camera != nil
        }
        guard hasCamera else { return nil }

        guard let camTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            logger.warning("Failed to create camera track in composition")
            return nil
        }

        var currentTime = CMTime.zero

        // Iterate ALL primary clips to maintain sync with the video track
        for (index, clip) in allClips.enumerated() {
            try await cancellationCheck?()

            let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)

            guard case .recording(let ref) = clip.content else {
                // Non-recording clips: insert gap to maintain sync
                currentTime = CMTimeAdd(currentTime, clipDuration)
                continue
            }

            guard let sources = resolveSources(ref.takeId),
                  let cameraPath = sources.camera?.path else {
                // No camera for this clip — insert gap to keep sync
                currentTime = CMTimeAdd(currentTime, clipDuration)
                continue
            }

            let asset: AVAsset
            do {
                asset = try await resolveAsset(
                    path: cameraPath,
                    proxyPath: resolver.cameraProxyPath,
                    resolver: resolver,
                    cache: &assetCache
                )
            } catch {
                logger.warning("Camera asset unavailable for clip \(clip.id): \(error.localizedDescription)")
                currentTime = CMTimeAdd(currentTime, clipDuration)
                continue
            }

            do {
                let cameraAssetTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceTrack = cameraAssetTracks.first else {
                    logger.warning("No camera video track for clip \(clip.id)")
                    currentTime = CMTimeAdd(currentTime, clipDuration)
                    continue
                }

                let startTime = CMTime(seconds: ref.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: ref.sourceOut - ref.sourceIn, preferredTimescale: 600)

                try camTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: camTrack, at: currentTime, duration: duration, speed: clip.speed
                )

                logger.debug("Camera clip \(index + 1): \(ref.sourceIn)s-\(ref.sourceOut)s")
                currentTime = CMTimeAdd(currentTime, effectiveDuration)
            } catch {
                logger.warning("Camera clip \(index + 1) failed, skipping: \(error.localizedDescription)")
                currentTime = CMTimeAdd(currentTime, clipDuration)
            }
        }

        return camTrack
    }

    // MARK: - Recording Audio Track

    private func buildRecordingAudioTrack(
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

            // Only recording clips contribute to recording audio
            guard case .recording(let ref) = clip.content else {
                // For non-recording clips, insert silence gap to maintain sync
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

    private func buildAdditionalAudioTracks(
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

    private func buildAudioClipTracks(
        into composition: AVMutableComposition,
        tracks: [Project.TimelineTrack],
        resolver: SourceResolver
    ) async -> [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] {
        var result: [(track: AVMutableCompositionTrack, clip: Project.TimelineClip)] = []

        for track in tracks where !track.isMuted {
            for clip in track.clips {
                guard case .audio(let ref) = clip.content else { continue }
                if let isMuted = clip.volume, isMuted == 0 { continue }

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

    // MARK: - Helpers

    /// Apply scaleTimeRange if speed != 1.0, return effective duration
    @discardableResult
    private func applySpeedIfNeeded(
        to track: AVMutableCompositionTrack,
        at time: CMTime,
        duration: CMTime,
        speed: Double
    ) -> CMTime {
        if speed != 1.0 {
            let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / speed)
            let insertedRange = CMTimeRange(start: time, duration: duration)
            track.scaleTimeRange(insertedRange, toDuration: scaledDuration)
            return scaledDuration
        }
        return duration
    }

    /// Resolve an asset from path, using proxy if available
    private func resolveAsset(
        path: String,
        proxyPath: String?,
        resolver: SourceResolver,
        cache: inout [String: AVAsset]
    ) async throws -> AVAsset {
        let effectivePath: String
        let assetURL: URL

        if let proxy = proxyPath, fileManager.fileExists(atPath: proxy) {
            effectivePath = proxy
            assetURL = URL(fileURLWithPath: proxy)
        } else {
            effectivePath = path
            assetURL = resolver.projectDirectory.appendingPathComponent(path)
        }

        if let cached = cache[effectivePath] {
            return cached
        }

        guard fileManager.fileExists(atPath: assetURL.path) else {
            logger.error("Source file not found at: \(assetURL.path)")
            throw CompositionBuilderError.sourceFileNotFound(assetURL.path)
        }

        logger.debug("Loading asset from: \(assetURL.path)")
        let asset = AVAsset(url: assetURL)
        cache[effectivePath] = asset
        return asset
    }
}

// MARK: - Errors

public enum CompositionBuilderError: Error, Equatable, Sendable {
    case failedToCreateTrack(String)
    case sourceFileNotFound(String)

    public var localizedDescription: String {
        switch self {
        case .failedToCreateTrack(let type):
            return "Failed to create \(type) track in composition"
        case .sourceFileNotFound(let path):
            return "Source file not found: \(path)"
        }
    }
}
