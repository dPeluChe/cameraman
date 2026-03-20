//
//  PreviewFrameExtractor.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreGraphics

extension PreviewEngine {
    /// Extract a frame at a specific time with overlays rendered
    /// - Parameter time: Time in seconds
    /// - Returns: CGImage of the frame with overlays applied
    /// - Throws: PreviewError if frame cannot be extracted
    public func extractFrame(at time: TimeInterval) async throws -> CGImage {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard let asset = self.composition else {
            throw PreviewError.playbackFailed("Composition not ready")
        }

        guard time >= 0 && time <= project.timeline.duration else {
            throw PreviewError.invalidTime(time)
        }

        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        assetImageGenerator.requestedTimeToleranceBefore = .zero
        assetImageGenerator.requestedTimeToleranceAfter = .zero

        // Apply videoComposition so camera PiP and layout transforms render
        if let videoComp = self.videoCompositionConfig {
            assetImageGenerator.videoComposition = videoComp
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let image = try assetImageGenerator.copyCGImage(at: cmTime, actualTime: nil)

        // Render overlays on the frame
        let imageWithOverlays = try await renderOverlays(on: image, at: time, project: project)

        return imageWithOverlays
    }

    /// Generate thumbnails for timeline
    /// - Parameters:
    ///   - count: Number of thumbnails to generate
    ///   - startTime: Start time for thumbnail range
    ///   - endTime: End time for thumbnail range
    /// - Returns: Array of (time, image) tuples
    /// - Throws: PreviewError if thumbnails cannot be generated
    public func generateThumbnails(
        count: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> [(TimeInterval, CGImage)] {
        guard project != nil else {
            throw PreviewError.noProjectLoaded
        }

        guard let asset = self.composition else {
            throw PreviewError.playbackFailed("Composition not ready")
        }

        guard count > 0 else {
            throw PreviewError.playbackFailed("Invalid thumbnail count: \(count)")
        }

        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        assetImageGenerator.maximumSize = CoreFoundation.CGSize(width: 160, height: 90)

        var thumbnails: [(TimeInterval, CGImage)] = []
        let duration = endTime - startTime
        let interval = duration / Double(count - 1)

        for i in 0..<count {
            let time = startTime + (Double(i) * interval)
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            // Use tolerance for faster thumbnail generation
            do {
                let image = try assetImageGenerator.copyCGImage(at: cmTime, actualTime: nil)
                thumbnails.append((time, image))
            } catch {
                // Skip failed thumbnails or retry
                logger.warning("Failed to generate thumbnail at \(time): \(error.localizedDescription)")
            }
        }

        return thumbnails
    }

    /// Extract a frame with zoom applied at a specific time
    /// - Parameter time: Time in seconds
    /// - Returns: CGImage of the frame with zoom applied
    /// - Throws: PreviewError if frame cannot be extracted
    public func extractFrameWithZoom(at time: TimeInterval) async throws -> CGImage {
        let frame = try await extractFrame(at: time)

        guard zoomEnabled, let zoomPlan = zoomPlan else {
            return frame
        }

        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        let canvasSize = CoreFoundation.CGSize(
            width: CGFloat(project.canvas.format.w),
            height: CGFloat(project.canvas.format.h)
        )

        return try await applyZoom(to: frame, at: time, zoomPlan: zoomPlan, canvasSize: canvasSize)
    }
}
