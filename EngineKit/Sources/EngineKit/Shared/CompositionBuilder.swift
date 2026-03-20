//
//  CompositionBuilder.swift
//  EngineKit
//
//  Shared composition building logic for Preview and Export.
//  Eliminates duplication of segment insertion, speed scaling,
//  and multi-track composition between the two pipelines.
//

import Foundation
import AVFoundation
import os.log

/// Builds an AVMutableComposition from project timeline segments.
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

    /// Callback for resolving sources per segment (supports multi-take)
    public typealias SourcesForSegment = (Project.Timeline.Segment) -> Project.Sources?

    /// Optional cancellation check — throw to cancel
    public typealias CancellationCheck = () async throws -> Void

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Build a full composition from project timeline
    public func buildComposition(
        project: Project,
        resolver: SourceResolver,
        resolveSources: SourcesForSegment,
        cancellationCheck: CancellationCheck? = nil
    ) async throws -> Result {
        let composition = AVMutableComposition()
        var assetCache: [String: AVAsset] = [:]

        // 1. Build video (screen) track
        let videoTrack = try await buildVideoTrack(
            into: composition,
            segments: project.timeline.segments,
            resolver: resolver,
            resolveSources: resolveSources,
            assetCache: &assetCache,
            cancellationCheck: cancellationCheck
        )

        // 2. Build camera track (if available)
        let cameraTrack = try await buildCameraTrack(
            into: composition,
            segments: project.timeline.segments,
            resolver: resolver,
            resolveSources: resolveSources,
            assetCache: &assetCache,
            cancellationCheck: cancellationCheck
        )

        // 3. Build system audio track (if available)
        let systemAudioTrack = try await buildAudioTrack(
            into: composition,
            segments: project.timeline.segments,
            audioPath: project.primarySources?.audio?.system?.path,
            trackLabel: "system audio",
            resolver: resolver,
            cancellationCheck: cancellationCheck
        )

        // 4. Build mic audio track (if available)
        let micAudioTrack = try await buildAudioTrack(
            into: composition,
            segments: project.timeline.segments,
            audioPath: project.primarySources?.audio?.mic?.path,
            trackLabel: "mic audio",
            resolver: resolver,
            cancellationCheck: cancellationCheck
        )

        return Result(
            composition: composition,
            videoTrack: videoTrack,
            cameraTrack: cameraTrack,
            systemAudioTrack: systemAudioTrack,
            micAudioTrack: micAudioTrack
        )
    }

    // MARK: - Video Track

    private func buildVideoTrack(
        into composition: AVMutableComposition,
        segments: [Project.Timeline.Segment],
        resolver: SourceResolver,
        resolveSources: SourcesForSegment,
        assetCache: inout [String: AVAsset],
        cancellationCheck: CancellationCheck?
    ) async throws -> AVMutableCompositionTrack {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompositionBuilderError.failedToCreateTrack("video")
        }

        var currentTime = CMTime.zero

        for (index, segment) in segments.enumerated() {
            try await cancellationCheck?()

            guard let sources = resolveSources(segment) else {
                logger.warning("No sources for segment \(segment.id), skipping")
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
                logger.warning("No video track in source for segment \(segment.id), skipping")
                continue
            }

            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
            let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)

            try videoTrack.insertTimeRange(
                CMTimeRangeMake(start: startTime, duration: duration),
                of: sourceTrack,
                at: currentTime
            )

            let effectiveDuration = applySpeedIfNeeded(
                to: videoTrack, at: currentTime, duration: duration, speed: segment.speed
            )

            logger.debug("Video segment \(index + 1): \(segment.sourceIn)s-\(segment.sourceOut)s, speed \(segment.speed)x")
            currentTime = CMTimeAdd(currentTime, effectiveDuration)
        }

        return videoTrack
    }

    // MARK: - Camera Track

    private func buildCameraTrack(
        into composition: AVMutableComposition,
        segments: [Project.Timeline.Segment],
        resolver: SourceResolver,
        resolveSources: SourcesForSegment,
        assetCache: inout [String: AVAsset],
        cancellationCheck: CancellationCheck?
    ) async throws -> AVMutableCompositionTrack? {
        // Check if any segment has camera
        let hasCamera = segments.contains { segment in
            resolveSources(segment)?.camera != nil
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

        for (index, segment) in segments.enumerated() {
            try await cancellationCheck?()

            let gapDuration = CMTime(
                seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                preferredTimescale: 600
            )

            guard let sources = resolveSources(segment),
                  let cameraPath = sources.camera?.path else {
                // No camera for this segment — insert gap to keep sync
                currentTime = CMTimeAdd(currentTime, gapDuration)
                continue
            }

            // Resolve camera asset (with optional proxy)
            let asset: AVAsset
            do {
                asset = try await resolveAsset(
                    path: cameraPath,
                    proxyPath: resolver.cameraProxyPath,
                    resolver: resolver,
                    cache: &assetCache
                )
            } catch {
                logger.warning("Camera asset unavailable for segment \(segment.id): \(error.localizedDescription)")
                currentTime = CMTimeAdd(currentTime, gapDuration)
                continue
            }

            do {
                let cameraAssetTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceTrack = cameraAssetTracks.first else {
                    logger.warning("No camera video track for segment \(segment.id)")
                    currentTime = CMTimeAdd(currentTime, gapDuration)
                    continue
                }

                let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)

                try camTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: camTrack, at: currentTime, duration: duration, speed: segment.speed
                )

                logger.debug("Camera segment \(index + 1): \(segment.sourceIn)s-\(segment.sourceOut)s")
                currentTime = CMTimeAdd(currentTime, effectiveDuration)
            } catch {
                logger.warning("Camera segment \(index + 1) failed, skipping: \(error.localizedDescription)")
                currentTime = CMTimeAdd(currentTime, gapDuration)
            }
        }

        return camTrack
    }

    // MARK: - Audio Track

    private func buildAudioTrack(
        into composition: AVMutableComposition,
        segments: [Project.Timeline.Segment],
        audioPath: String?,
        trackLabel: String,
        resolver: SourceResolver,
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

        for segment in segments {
            try await cancellationCheck?()

            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
            let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)

            do {
                try audioTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceAudioTrack,
                    at: currentTime
                )

                let effectiveDuration = applySpeedIfNeeded(
                    to: audioTrack, at: currentTime, duration: duration, speed: segment.speed
                )

                currentTime = CMTimeAdd(currentTime, effectiveDuration)
            } catch {
                logger.error("Failed to insert audio at \(segment.sourceIn)s: \(error.localizedDescription)")
                let gapDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / segment.speed)
                currentTime = CMTimeAdd(currentTime, gapDuration)
            }
        }

        logger.debug("\(trackLabel) track built successfully")
        return audioTrack
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
        // Determine effective path (proxy or original)
        let effectivePath: String
        let assetURL: URL

        if let proxy = proxyPath, fileManager.fileExists(atPath: proxy) {
            effectivePath = proxy
            assetURL = URL(fileURLWithPath: proxy)
        } else {
            effectivePath = path
            assetURL = resolver.projectDirectory.appendingPathComponent(path)
        }

        // Check cache
        if let cached = cache[effectivePath] {
            return cached
        }

        // Verify file exists
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
