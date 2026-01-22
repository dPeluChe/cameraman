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

        // Use primary sources for initial validation, but we'll load per-segment sources later
        guard project.primarySources != nil else {
            throw PreviewError.playbackFailed("No sources found")
        }

        // Create AVMutableComposition with segments
        let composition = AVMutableComposition()

        // Add composition track for screen
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        guard let videoTrack = compositionVideoTrack else {
            throw PreviewError.playbackFailed("Failed to create composition video track")
        }

        var insertTime = CMTime.zero

        // Cache for loaded assets to avoid reloading the same file multiple times
        var assetCache: [String: AVAsset] = [:]

        // Apply segments (trims, cuts, speed changes)
        for segment in project.timeline.segments {
            // Resolve sources for this segment
            guard let sources = resolveSources(for: segment.takeId) else {
                // If we can't resolve sources, we skip this segment or insert black gap?
                // For now, skipping, but keeping time alignment might require inserting empty time.
                continue
            }

            let sourcePath = sources.screen.path

            // Load asset (cached)
            let asset: AVAsset
            if let cached = assetCache[sourcePath] {
                asset = cached
            } else {
                let assetURL: URL
                if let projectDir = projectDirectory {
                    assetURL = URL(fileURLWithPath: projectDir).appendingPathComponent(sourcePath)
                } else {
                    assetURL = URL(fileURLWithPath: sourcePath)
                }
                asset = AVAsset(url: assetURL)
                assetCache[sourcePath] = asset
            }

            // Load screen asset tracks
            let screenAssetTracks = try await asset.loadTracks(withMediaType: .video)
            guard let screenTrack = screenAssetTracks.first else {
                // Skip if no video track
                continue
            }

            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
            let endTime = CMTime(seconds: segment.sourceOut, preferredTimescale: 600)
            let duration = CMTimeSubtract(endTime, startTime)

            // Time range in source
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            try videoTrack.insertTimeRange(
                timeRange,
                of: screenTrack,
                at: insertTime
            )

            // Advance insert time by segment duration (adjusted for speed)
            let segmentDuration = CMTime(
                seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                preferredTimescale: 600
            )
            insertTime = CMTimeAdd(insertTime, segmentDuration)
        }

        // Handle camera track if present (Simplified for now - assumes primary take camera or needs complexity)
        if project.primarySources?.camera != nil {
            // Add camera as separate track for PiP/side-by-side
            // This is a simplified version - full implementation would position camera based on canvas layout
        }

        // Create player item with composition
        // Note: AVPlayerItem is main actor-isolated, creating it on the main actor
        let playerItem = await MainActor.run {
            AVPlayerItem(asset: composition)
        }
        player = AVPlayer(playerItem: playerItem)
        self.composition = composition

        // Add time observer for current time tracking
        // Note: In a real implementation, we would add a periodic time observer here
        // For now, we'll track time manually during playback
    }
}
