//
//  GIFExportSession.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

extension ExportEngine {
    /// Perform the actual GIF export work
    func performGIFExport(
        jobId: JobId,
        projectId: ProjectId,
        project: Project,
        preset: ExportPreset,
        options: ExportOptions
    ) async {
        let startTime = Date()
        logger.debug("Starting GIF export performance for job: \(jobId.uuidString)")

        do {
            let projectDirectory = try await projectStore.projectDirectoryURL(for: projectId)
            let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)

            // Create renders directory if it doesn't exist
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            logger.debug("Created renders directory: \(outputDirectory.path)")

            // Generate output filename with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputFilename = options.outputFilename ?? "export_\(timestamp).gif"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            logger.info("Output GIF file: \(outputFilename)")

            // Stage 1: Validation
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .validation, progress: 0.02)
            logger.debug("Validating project for GIF export")
            
            // Validate total duration for GIF export (warn if > 30 seconds)
            let totalDuration = project.timeline.duration
            if totalDuration > 30.0 {
                logger.warning("GIF export duration (\(totalDuration)s) exceeds recommended maximum of 30s. File may be very large.")
            }

            // Stage 2: Composition Building (was Asset Loading)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.1)
            logger.debug("Building composition from \(project.timeline.segments.count) segments")

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.compositionFailed("Failed to create video track")
            }

            var currentTime = CMTime.zero
            var assetCache: [String: AVAsset] = [:]

            // Apply segments (trims, cuts, speed)
            for segment in project.timeline.segments {
                try await checkCancellation(jobId: jobId)
                
                guard let sources = resolveSources(for: segment.takeId, in: project) else {
                    logger.warning("Could not resolve sources for segment \(segment.id), skipping")
                    continue
                }
                
                let sourcePath = sources.screen.path
                let asset: AVAsset
                
                if let cached = assetCache[sourcePath] {
                    asset = cached
                } else {
                    let assetURL = projectDirectory.appendingPathComponent(sourcePath)
                    asset = AVAsset(url: assetURL)
                    assetCache[sourcePath] = asset
                }
                
                let videoAssetTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceVideoTrack = videoAssetTracks.first else {
                    logger.warning("No video track found in source asset for segment \(segment.id), skipping")
                    continue
                }

                let start = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: start, duration: duration)

                try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: currentTime)
                
                // Handle speed changes
                if segment.speed != 1.0 {
                    let insertedRange = CMTimeRange(start: currentTime, duration: duration)
                    let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / segment.speed)
                    videoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                    currentTime = CMTimeAdd(currentTime, scaledDuration)
                } else {
                    currentTime = CMTimeAdd(currentTime, duration)
                }
            }

            // Get GIF export options
            let gifOptions = options.gifOptions ?? .default
            logger.debug("GIF options - quality: \(gifOptions.quality), loopCount: \(gifOptions.loopCount)")

            // Stage 3: Extract frames from composition
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .videoCompositionSetup, progress: 0.2)
            logger.debug("Extracting frames for GIF")

            // Calculate frame rate
            let frameRate: Int = gifOptions.frameRate ?? preset.output.fps
            
            // Extract frames from video
            let frames = try await extractFramesFromVideo(
                asset: composition,
                duration: currentTime.seconds,
                frameRate: frameRate,
                maxSize: gifOptions.maxSize ?? preset.output.width,
                progress: { [weak self] progress in
                    guard let self else { return }
                    await self.updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.2 + progress * 0.4)
                }
            )

            logger.debug("Extracted \(frames.count) frames")

            // Stage 4: Encode GIF
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .exporting(progress: 0.0), progress: 0.6)
            logger.debug("Encoding GIF")

            try await encodeGIFFromFrames(
                frames: frames,
                outputURL: outputURL,
                frameRate: frameRate,
                gifOptions: gifOptions,
                progress: { [weak self] progress in
                    guard let self else { return }
                    await self.updateExportStage(jobId: jobId, stage: .exporting(progress: progress), progress: 0.6 + progress * 0.35)
                }
            )

            logger.debug("GIF encoding completed")

            // Stage 5: Verify output
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .verification, progress: 0.97)
            
            // Verify output file exists and has content
            let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes?[.size] as? UInt64 ?? 0

            guard fileSize > 0 else {
                throw ExportError.outputFileEmpty
            }

            logger.info("Output GIF file verified: \(fileSize) bytes")

            // Stage 6: Cleanup
            await updateExportStage(jobId: jobId, stage: .cleanup, progress: 0.99)
            
            // Create export result
            let result = ExportResult(
                outputURL: outputURL,
                fileSize: fileSize,
                duration: totalDuration,
                preset: preset
            )

            // Calculate total export time
            let totalTime = Date().timeIntervalSince(startTime)
            logExportSummary(jobId: jobId, result: result, duration: totalTime)

            // Complete job
            await jobQueue.completeJob(jobId: jobId)
            await cleanupExport(jobId: jobId)

        } catch {
            // Log error with stage information
            let currentStage = exportStages[jobId] ?? .validation
            logExportError(jobId: jobId, error: error, stage: currentStage)

            // Fail job with error
            let jobError = Job.JobError(
                code: "GIF_EXPORT_FAILED",
                message: error.localizedDescription,
                details: ["original_error": .string(String(describing: error))],
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await cleanupExport(jobId: jobId)
        }
    }

    /// Extract frames from video asset for GIF encoding
    private func extractFramesFromVideo(
        asset: AVAsset,
        duration: TimeInterval,
        frameRate: Int,
        maxSize: Int,
        progress: @escaping (Double) async -> Void
    ) async throws -> [CGImage] {
        logger.debug("Starting frame extraction at \(frameRate) fps, max size: \(maxSize)")

        // Create asset reader
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            throw ExportError.compositionFailed("Failed to create asset reader")
        }

        // Get video track
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        // Configure video output with desired frame rate
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        assetReader.add(videoOutput)
        assetReader.startReading()

        // Calculate time intervals for frame extraction
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        var frames: [CGImage] = []
        var currentTime = CMTime.zero
        var frameCount = 0
        let totalEstimatedFrames = Int(duration * Double(frameRate))

        logger.debug("Extracting approximately \(totalEstimatedFrames) frames")

        // Extract frames at specified intervals
        while assetReader.status == .reading {
            autoreleasepool {
                guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                    return
                }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                // Check if this frame is at the desired time interval
                if currentTime <= presentationTime {
                    if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        // Create CIImage from CVImageBuffer
                        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

                        // Calculate dimensions to fit within maxSize while maintaining aspect ratio
                        let sourceWidth = CGFloat(CVPixelBufferGetWidthOfPlane(imageBuffer, 0))
                        let sourceHeight = CGFloat(CVPixelBufferGetHeightOfPlane(imageBuffer, 0))
                        let aspectRatio = sourceWidth / sourceHeight

                        var targetWidth = CGFloat(maxSize)
                        var targetHeight = CGFloat(maxSize)

                        if aspectRatio > 1.0 {
                            // Landscape
                            targetHeight = targetWidth / aspectRatio
                        } else {
                            // Portrait
                            targetWidth = targetHeight * aspectRatio
                        }

                        // Scale image
                        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: targetWidth / sourceWidth, y: targetHeight / sourceHeight))

                        // Render to CGImage
                        let context = CIContext(options: [.useSoftwareRenderer: false])
                        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                            frames.append(cgImage)
                            frameCount += 1

                            // Update progress
                            let frameProgress = Double(frameCount) / Double(max(totalEstimatedFrames, 1))
                            Task {
                                await progress(min(frameProgress, 0.99))
                            }
                        }

                        // Advance to next frame time
                        currentTime = CMTimeAdd(currentTime, frameDuration)
                    }
                }
            }

            // Check if we've extracted enough frames
            if frameCount >= totalEstimatedFrames {
                break
            }
        }

        // Clean up
        assetReader.cancelReading()

        logger.debug("Extracted \(frames.count) frames successfully")

        return frames
    }

    /// Encode GIF from array of CGImage frames
    private func encodeGIFFromFrames(
        frames: [CGImage],
        outputURL: URL,
        frameRate: Int,
        gifOptions: GIFExportOptions,
        progress: @escaping (Double) async -> Void
    ) async throws {
        logger.debug("Encoding \(frames.count) frames to GIF at \(frameRate) fps")

        // Calculate frame delay in centiseconds
        let frameDelay = 1.0 / Double(frameRate)
        let frameDelayCs = Int(frameDelay * 100) // Convert to centiseconds

        logger.debug("Frame delay: \(frameDelayCs) centiseconds")

        // Create GIF destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            logger.error("Failed to create GIF destination")
            throw ExportError.exportFailed("Failed to create GIF destination")
        }

        // Set GIF properties
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: gifOptions.loopCount
            ]
        ]

        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Encode each frame
        for (index, frame) in frames.enumerated() {
            autoreleasepool {
                // Set frame properties
                let frameProperties: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: Double(frameDelayCs) / 100.0
                    ]
                ]

                // Add frame to GIF
                CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)

                // Update progress
                let frameProgress = Double(index + 1) / Double(frames.count)
                Task {
                    await progress(frameProgress)
                }
            }

            // Check for cancellation
            try? Task.checkCancellation()
        }

        // Finalize GIF
        guard CGImageDestinationFinalize(destination) else {
            logger.error("Failed to finalize GIF")
            throw ExportError.exportFailed("Failed to finalize GIF")
        }

        logger.debug("GIF encoding completed successfully")
    }
}
