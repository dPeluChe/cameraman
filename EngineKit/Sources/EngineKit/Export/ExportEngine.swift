//
//  ExportEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreFoundation
import QuartzCore
import AppKit
import os.log
import ImageIO
import UniformTypeIdentifiers

/// ExportEngine handles video export with trims, cuts, layouts, and overlays applied
/// Supports downsampling from native resolution to 1080p, with configurable presets
/// Enhanced with structured logging, detailed progress tracking, and cancellation support
public actor ExportEngine {
    /// Shared job queue for async operations
    private let jobQueue: JobQueue
    /// Project store for reading projects
    private let projectStore: ProjectStore
    /// File manager for file operations
    private let fileManager: FileManager
    /// Structured logging
    private let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "ExportEngine")
    /// Export stage tracking for detailed progress
    private var exportStages: [JobId: [ExportStage]] = [:]

    /// Initialize ExportEngine
    /// - Parameters:
    ///   - jobQueue: JobQueue for managing export jobs
    ///   - projectStore: ProjectStore for reading projects
    public init(jobQueue: JobQueue, projectStore: ProjectStore) {
        self.jobQueue = jobQueue
        self.projectStore = projectStore
        self.fileManager = FileManager.default
    }

    // MARK: - Export Stage Tracking

    /// Export stage for detailed progress tracking
    private enum ExportStage {
        case validation
        case assetLoading
        case compositionBuilding
        case videoCompositionSetup
        case exportSessionConfig
        case exporting(progress: Double)
        case verification
        case cleanup

        var description: String {
            switch self {
            case .validation: return "Validating project and source files"
            case .assetLoading: return "Loading video and audio assets"
            case .compositionBuilding: return "Building timeline composition"
            case .videoCompositionSetup: return "Setting up video composition"
            case .exportSessionConfig: return "Configuring export session"
            case .exporting(let p): return "Exporting video (\(Int(p * 100))%)"
            case .verification: return "Verifying output file"
            case .cleanup: return "Cleaning up temporary files"
            }
        }
    }

    /// Initialize export stages for a job
    private func initializeExportStages(for jobId: JobId, project: Project, preset: ExportPreset) {
        exportStages[jobId] = [
            .validation,
            .assetLoading,
            .compositionBuilding,
            .videoCompositionSetup,
            .exportSessionConfig,
            .exporting(progress: 0.0),
            .verification,
            .cleanup
        ]

        logger.debug("Initialized export stages for job \(jobId.uuidString): \(preset.name)")
    }

    /// Update export stage with logging
    private func updateExportStage(jobId: JobId, stage: ExportStage, progress: Double) async {
        exportStages[jobId]?.append(stage)

        // Log the stage change with structured data
        logger.debug("Export stage: \(stage.description) (progress: \(Int(progress * 100))%) jobId: \(jobId.uuidString)")

        // Update job progress
        await jobQueue.updateJobProgress(jobId: jobId, progress: progress)
    }

    /// Log export summary
    private func logExportSummary(jobId: JobId, result: ExportResult, duration: TimeInterval) {
        logger.info("Export completed successfully - jobId: \(jobId.uuidString), outputFile: \(result.outputURL.lastPathComponent), fileSize: \(result.fileSize), duration: \(result.duration)s, preset: \(result.preset.id), exportTime: \(duration)s")
    }

    /// Log export error with structured details
    private func logExportError(jobId: JobId, error: Error, stage: ExportStage) {
        logger.error("Export failed at stage: \(stage.description) - jobId: \(jobId.uuidString), stage: \(stage.description), error: \(error.localizedDescription), errorType: \(String(describing: type(of: error)))")
    }

    /// Check for cancellation and throw if needed
    private func checkCancellation(jobId: JobId) async throws {
        if Task.isCancelled {
            logger.info("Export cancelled by user at job: \(jobId.uuidString)")
            await cleanupExport(jobId: jobId)
            throw ExportError.exportFailed("Export was cancelled")
        }
    }

    /// Cleanup export resources
    private func cleanupExport(jobId: JobId) async {
        logger.debug("Cleaning up export resources for job: \(jobId.uuidString)")
        exportStages.removeValue(forKey: jobId)
    }

    /// Start an export job for a project
    /// - Parameters:
    ///   - projectId: Project to export
    ///   - preset: Export preset configuration
    ///   - options: Additional export options
    /// - Returns: JobId for tracking progress
    public func export(
        projectId: ProjectId,
        preset: ExportPreset = .web1080h264,
        options: ExportOptions = .default
    ) async throws -> JobId {
        logger.info("Starting export for project: \(projectId.uuidString), preset: \(preset.id)")

        // Load project
        let project = try await projectStore.loadProject(projectId: projectId)
        logger.debug("Loaded project '\(project.name)' with \(project.timeline.segments.count) segments")

        // Validate project has segments
        guard !project.timeline.segments.isEmpty else {
            logger.error("Export failed: project has no timeline segments")
            throw ExportError.noSegments
        }

        // Validate source files exist
        try await validateSourceFiles(for: project, projectId: projectId)
        logger.debug("All source files validated successfully")

        // Create job
        let jobId = await jobQueue.createJob(type: .export, projectId: projectId)
        logger.info("Created export job: \(jobId.uuidString)")

        // Initialize export stages for tracking
        initializeExportStages(for: jobId, project: project, preset: preset)

        // Start export task
        let task = Task {
            await performExport(
                jobId: jobId,
                projectId: projectId,
                project: project,
                preset: preset,
                options: options
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)
        logger.debug("Export job started: \(jobId.uuidString)")

        return jobId
    }

    /// Start a GIF export job for a project
    /// - Parameters:
    ///   - projectId: Project to export as GIF
    ///   - preset: Export preset (should be .animatedGIF or compatible)
    ///   - options: Additional export options including GIF-specific settings
    /// - Returns: JobId for tracking progress
    public func exportGIF(
        projectId: ProjectId,
        preset: ExportPreset = .animatedGIF,
        options: ExportOptions = .default
    ) async throws -> JobId {
        logger.info("Starting GIF export for project: \(projectId.uuidString), preset: \(preset.id)")

        // Load project
        let project = try await projectStore.loadProject(projectId: projectId)
        logger.debug("Loaded project '\(project.name)' with \(project.timeline.segments.count) segments")

        // Validate project has segments
        guard !project.timeline.segments.isEmpty else {
            logger.error("GIF export failed: project has no timeline segments")
            throw ExportError.noSegments
        }

        // Validate source files exist
        try await validateSourceFiles(for: project, projectId: projectId)
        logger.debug("All source files validated successfully")

        // Create job
        let jobId = await jobQueue.createJob(type: .export, projectId: projectId)
        logger.info("Created GIF export job: \(jobId.uuidString)")

        // Initialize export stages for tracking
        initializeExportStages(for: jobId, project: project, preset: preset)

        // Start GIF export task
        let task = Task {
            await performGIFExport(
                jobId: jobId,
                projectId: projectId,
                project: project,
                preset: preset,
                options: options
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)
        logger.debug("GIF export job started: \(jobId.uuidString)")

        return jobId
    }

    /// Cancel an export job
    /// - Parameter jobId: Job to cancel
    /// - Throws: ExportError if cancellation fails
    public func cancelExport(jobId: JobId) async throws {
        logger.info("Cancelling export job: \(jobId.uuidString)")

        do {
            try await jobQueue.cancelJob(jobId: jobId)
            logger.info("Export job cancelled successfully: \(jobId.uuidString)")
        } catch {
            logger.error("Failed to cancel export job: \(jobId.uuidString), error: \(error.localizedDescription)")
            throw ExportError.exportFailed("Failed to cancel export: \(error.localizedDescription)")
        }
    }

    /// Get the shared job queue for export operations
    /// - Returns: JobQueue instance
    public func getJobQueue() -> JobQueue {
        return self.jobQueue
    }

    /// Perform the actual GIF export work
    private func performGIFExport(
        jobId: JobId,
        projectId: ProjectId,
        project: Project,
        preset: ExportPreset,
        options: ExportOptions
    ) async {
        let startTime = Date()
        logger.debug("Starting GIF export performance for job: \(jobId.uuidString)")

        do {
            let projectDirectory = getProjectDirectory(for: projectId)
            let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)

            // Create renders directory if it doesn't exist
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            logger.debug("Created renders directory: \(outputDirectory.path)")

            // Generate output filename with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputFilename = options.outputFilename ?? "export_\(timestamp).gif"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            logger.info("Output GIF file: \(outputFilename)")

            // Stage 1: Validation (0.0 - 0.1)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .validation, progress: 0.02)
            logger.debug("Validating project for GIF export")
            logger.debug("Project has \(project.timeline.segments.count) segments")

            // Validate total duration for GIF export (warn if > 30 seconds)
            let totalDuration = project.timeline.duration
            if totalDuration > 30.0 {
                logger.warning("GIF export duration (\(totalDuration)s) exceeds recommended maximum of 30s. File may be very large.")
            }

            // Stage 2: Load and validate source assets (0.1 - 0.2)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .assetLoading, progress: 0.1)
            logger.debug("Loading screen asset from: \(project.sources.screen.path)")

            let screenAsset = AVAsset(url: projectDirectory.appendingPathComponent(project.sources.screen.path))

            // Verify screen asset is readable
            let isScreenReadable = try await screenAsset.load(.isReadable)
            guard isScreenReadable else {
                logger.error("Screen asset is not readable")
                throw ExportError.assetNotReadable("screen")
            }
            logger.debug("Screen asset loaded successfully")

            // Get GIF export options
            let gifOptions = options.gifOptions ?? .default
            logger.debug("GIF options - quality: \(gifOptions.quality), loopCount: \(gifOptions.loopCount), maxSize: \(gifOptions.maxSize?.description ?? "none"), frameRate: \(gifOptions.frameRate?.description ?? "preset default")")

            // Stage 3: Extract frames from video (0.2 - 0.6)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.2)
            logger.debug("Extracting frames for GIF")

            // Calculate frame rate
            let frameRate: Int
            if let customFrameRate = gifOptions.frameRate {
                frameRate = customFrameRate
            } else {
                frameRate = preset.output.fps
            }

            // Calculate total number of frames
            let totalFrames = Int(totalDuration * Double(frameRate))
            logger.debug("Extracting \(totalFrames) frames at \(frameRate) fps")

            // Extract frames from video
            let frames = try await extractFramesFromVideo(
                asset: screenAsset,
                project: project,
                frameRate: frameRate,
                maxSize: gifOptions.maxSize ?? preset.output.width,
                progress: { progress in
                    Task { [weak self] in
                        await self?.updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.2 + progress * 0.4)
                    }
                }
            )

            logger.debug("Extracted \(frames.count) frames")

            // Stage 4: Encode GIF (0.6 - 0.95)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .videoCompositionSetup, progress: 0.6)
            logger.debug("Encoding GIF")

            try await encodeGIFFromFrames(
                frames: frames,
                outputURL: outputURL,
                frameRate: frameRate,
                gifOptions: gifOptions,
                progress: { progress in
                    Task { [weak self] in
                        await self?.updateExportStage(jobId: jobId, stage: .exporting(progress: progress), progress: 0.6 + progress * 0.35)
                    }
                }
            )

            logger.debug("GIF encoding completed")

            // Stage 5: Verify output (0.95 - 1.0)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .verification, progress: 0.97)
            logger.debug("Verifying GIF output file")

            // Verify output file exists and has content
            let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes?[.size] as? UInt64 ?? 0

            guard fileSize > 0 else {
                logger.error("Output GIF file is empty")
                throw ExportError.outputFileEmpty
            }

            logger.info("Output GIF file verified: \(fileSize) bytes")

            // Warn if file is very large
            let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
            if fileSizeMB > 50.0 {
                logger.warning("GIF file size (\(String(format: "%.2f", fileSizeMB))MB) exceeds recommended maximum of 50MB. Consider reducing quality or dimensions.")
            }

            // Stage 6: Cleanup (1.0)
            await updateExportStage(jobId: jobId, stage: .cleanup, progress: 0.99)
            logger.debug("Cleaning up GIF export resources")

            // Create export result
            let gifDuration = totalDuration
            let result = ExportResult(
                outputURL: outputURL,
                fileSize: fileSize,
                duration: gifDuration,
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
            let currentStage = exportStages[jobId]?.last ?? .validation
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
        project: Project,
        frameRate: Int,
        maxSize: Int,
        progress: @escaping (Double) async -> Void
    ) async throws -> [CGImage] {
        logger.debug("Starting frame extraction at \(frameRate) fps, max size: \(maxSize)")

        // Create asset reader
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            logger.error("Failed to create asset reader")
            throw ExportError.compositionFailed("Failed to create asset reader")
        }

        // Get video track
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            logger.error("No video track found")
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
        let totalEstimatedFrames = Int(project.timeline.duration * Double(frameRate))

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

    /// Perform the actual export work
    private func performExport(
        jobId: JobId,
        projectId: ProjectId,
        project: Project,
        preset: ExportPreset,
        options: ExportOptions
    ) async {
        let startTime = Date()
        logger.debug("Starting export performance for job: \(jobId.uuidString)")

        do {
            let projectDirectory = getProjectDirectory(for: projectId)
            let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)

            // Create renders directory if it doesn't exist
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            logger.debug("Created renders directory: \(outputDirectory.path)")

            // Generate output filename with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputFilename = "export_\(timestamp).mp4"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            logger.info("Output file: \(outputFilename)")

            // Stage 1: Validation (0.0 - 0.1)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .validation, progress: 0.02)
            logger.debug("Validating project segments")
            logger.debug("Project has \(project.timeline.segments.count) segments")

            // Stage 2: Load and validate source assets (0.1 - 0.2)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .assetLoading, progress: 0.1)
            logger.debug("Loading screen asset from: \(project.sources.screen.path)")

            let screenAsset = AVAsset(url: projectDirectory.appendingPathComponent(project.sources.screen.path))

            // Verify screen asset is readable
            let isScreenReadable = try await screenAsset.load(.isReadable)
            guard isScreenReadable else {
                logger.error("Screen asset is not readable")
                throw ExportError.assetNotReadable("screen")
            }
            logger.debug("Screen asset loaded successfully")

            // Check for cancellation after asset loading
            try await checkCancellation(jobId: jobId)

            // Stage 3: Create composition with trims/cuts applied (0.2 - 0.4)
            await updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.25)
            logger.debug("Building video composition from timeline segments")

            let composition = AVMutableComposition()

            // Build video track from timeline segments
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                logger.error("Failed to create video track")
                throw ExportError.compositionFailed("Failed to create video track")
            }

            var currentTime = CMTime.zero
            let videoAssetTracks = try await screenAsset.loadTracks(withMediaType: .video)

            guard let sourceVideoTrack = videoAssetTracks.first else {
                logger.error("No video track found in source asset")
                throw ExportError.noVideoTrack
            }

            logger.debug("Applying \(project.timeline.segments.count) timeline segments")

            // Apply timeline segments (trims, cuts, speed)
            for (index, segment) in project.timeline.segments.enumerated() {
                try await checkCancellation(jobId: jobId)

                let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)

                // Calculate scaled duration based on speed
                let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / segment.speed)

                try videoTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceVideoTrack,
                    at: currentTime
                )

                logger.debug("Segment \(index + 1): source \(segment.sourceIn)s - \(segment.sourceOut)s, speed \(segment.speed)x")

                currentTime = CMTimeAdd(currentTime, scaledDuration)
            }

            // Build audio track if available
            var audioAsset: AVAsset?
            var audioTrack: AVMutableCompositionTrack?

            if let audioPath = project.sources.audio?.system?.path {
                logger.debug("Loading system audio from: \(audioPath)")
                audioAsset = AVAsset(url: projectDirectory.appendingPathComponent(audioPath))
                let audioAssetTracks = try await audioAsset!.loadTracks(withMediaType: .audio)

                if let sourceAudioTrack = audioAssetTracks.first {
                    audioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )

                    if let audioTrack = audioTrack {
                        currentTime = CMTime.zero
                        for segment in project.timeline.segments {
                            try await checkCancellation(jobId: jobId)

                            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                            let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)
                            let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / segment.speed)

                            try? audioTrack.insertTimeRange(
                                CMTimeRangeMake(start: startTime, duration: duration),
                                of: sourceAudioTrack,
                                at: currentTime
                            )

                            currentTime = CMTimeAdd(currentTime, scaledDuration)
                        }
                        logger.debug("Audio track built successfully")
                    }
                }
            } else {
                logger.debug("No audio track available")
            }

            // Stage 4: Apply layout and transforms (0.4 - 0.5)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .videoCompositionSetup, progress: 0.45)
            logger.debug("Setting up video composition with preset: \(preset.name)")

            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CoreFoundation.CGSize(width: CGFloat(preset.output.width), height: CGFloat(preset.output.height))
            videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(preset.output.fps))

            logger.debug("Render size: \(preset.output.width)x\(preset.output.height) @ \(preset.output.fps)fps")

            // Create video composition instruction
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

            // Create layer instruction for screen track
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

            // Apply downscale from native resolution to output resolution
            let sourceSize = CoreFoundation.CGSize(
                width: CGFloat(project.sources.screen.size.w),
                height: CGFloat(project.sources.screen.size.h)
            )

            logger.debug("Source size: \(project.sources.screen.size.w)x\(project.sources.screen.size.h)")

            let transform = calculateDownscaleTransform(
                from: sourceSize,
                to: videoComposition.renderSize,
                contentMode: project.canvas.background.fitMode ?? "fill"
            )

            // Apply zoom transforms if enabled
            if options.applyZoom, let zoomPlan = options.zoomPlan {
                logger.debug("Applying zoom transforms with \(zoomPlan.keyframes.count) keyframes")
                try await applyZoomTransforms(
                    to: layerInstruction,
                    zoomPlan: zoomPlan,
                    baseTransform: transform,
                    sourceSize: sourceSize,
                    renderSize: videoComposition.renderSize,
                    compositionDuration: composition.duration
                )
            } else {
                // No zoom, just apply base transform
                layerInstruction.setTransform(transform, at: .zero)
            }

            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]

            // Stage 5: Setup export session (0.5 - 0.6)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .exportSessionConfig, progress: 0.55)
            logger.debug("Configuring export session")

            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                logger.error("Failed to create export session")
                throw ExportError.exportSessionCreationFailed
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4

            // Apply burn-in captions if enabled
            if options.burnCaptions || preset.options.burnCaptions {
                logger.debug("Burn-in captions enabled, applying caption layer")
                do {
                    let animationTool = try await createCaptionLayer(
                        for: project,
                        projectId: projectId,
                        renderSize: videoComposition.renderSize,
                        compositionDuration: composition.duration
                    )
                    videoComposition.animationTool = animationTool
                    exportSession.videoComposition = videoComposition
                    logger.debug("Caption layer applied successfully")
                } catch {
                    logger.error("Failed to apply caption layer: \(error.localizedDescription)")
                    // Continue export without captions if caption layer fails
                }
            } else {
                exportSession.videoComposition = videoComposition
            }

            logger.debug("Export session configured successfully")

            // Stage 6: Perform export with progress monitoring (0.6 - 0.95)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .exportSessionConfig, progress: 0.6)
            logger.debug("Starting AVFoundation export")

            // Monitor export progress
            let progressTask = Task {
                while !Task.isCancelled && exportSession.status == .exporting {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    let progress = Float(exportSession.progress)
                    let overallProgress = Double(progress * 0.35 + 0.6) // Map to 0.6-0.95 range
                    await updateExportStage(jobId: jobId, stage: .exporting(progress: Double(progress)), progress: overallProgress)
                }
            }

            await exportSession.export()
            progressTask.cancel()

            logger.debug("AVFoundation export completed")

            // Stage 7: Verify output (0.95 - 1.0)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .verification, progress: 0.97)
            logger.debug("Verifying output file")

            guard exportSession.status == .completed else {
                logger.error("Export session failed with status: \(exportSession.status.rawValue)")
                if let error = exportSession.error {
                    logger.error("Export error: \(error.localizedDescription)")
                }
                throw ExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
            }

            // Verify output file exists and has content
            let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes?[.size] as? UInt64 ?? 0

            guard fileSize > 0 else {
                logger.error("Output file is empty")
                throw ExportError.outputFileEmpty
            }

            logger.info("Output file verified: \(fileSize) bytes")

            // Stage 8: Cleanup (1.0)
            await updateExportStage(jobId: jobId, stage: .cleanup, progress: 0.99)
            logger.debug("Cleaning up export resources")

            // Create export result
            let exportDuration = composition.duration.seconds
            let result = ExportResult(
                outputURL: outputURL,
                fileSize: fileSize,
                duration: exportDuration,
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
            let currentStage = exportStages[jobId]?.last ?? .validation
            logExportError(jobId: jobId, error: error, stage: currentStage)

            // Fail job with error
            let jobError = Job.JobError(
                code: "EXPORT_FAILED",
                message: error.localizedDescription,
                details: ["original_error": .string(String(describing: error))],
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await cleanupExport(jobId: jobId)
        }
    }

    /// Create caption layer for burn-in captions
    /// - Parameters:
    ///   - project: Project with captions
    ///   - projectId: Project ID for file path resolution
    ///   - renderSize: Size of the output video
    ///   - compositionDuration: Duration of the composition
    /// - Returns: AVVideoCompositionCoreAnimationTool with caption layer
    private func createCaptionLayer(
        for project: Project,
        projectId: ProjectId,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws -> AVVideoCompositionCoreAnimationTool {
        logger.debug("Creating caption layer for burn-in")

        // Load captions from project
        guard let captionsConfig = project.captions else {
            logger.warning("No captions configured in project")
            throw ExportError.exportFailed("No captions available for burn-in")
        }

        // Load caption file
        let projectDirectory = getProjectDirectory(for: projectId)
        let captionPath = projectDirectory.appendingPathComponent(captionsConfig.srtPath)

        guard fileManager.fileExists(atPath: captionPath.path) else {
            logger.error("Caption file not found: \(captionPath)")
            throw ExportError.sourceFileNotFound(captionsConfig.srtPath)
        }

        // Parse captions
        let captionsManager = CaptionsManager()
        try await captionsManager.loadCaptions(from: captionPath.path)
        let captions = await captionsManager.getAllCaptions()

        logger.debug("Loaded \(captions.count) captions for burn-in")

        // Create parent layer for video composition
        let parentLayer = CALayer()
        parentLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)

        // Create video layer
        let videoLayer = CALayer()
        videoLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Create caption layer
        let captionLayer = CALayer()
        captionLayer.frame = CoreFoundation.CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(captionLayer)

        // Get caption style
        let style = await captionsManager.getStyle()

        // Create text attributes
        let fontSize = style.fontSize * CGFloat(renderSize.height)
        let font = NSFont(name: style.fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

        // Calculate text position
        let yPos = (1.0 - style.verticalPosition) * CGFloat(renderSize.height) - fontSize
        let maxLineWidth = style.maxLineWidth * CGFloat(renderSize.width)

        // Process each caption and create animation
        for caption in captions {
            let startTime = CMTime(seconds: caption.start, preferredTimescale: 600)
            let endTime = CMTime(seconds: caption.end, preferredTimescale: 600)

            // Create text layer for this caption
            let textLayer = CATextLayer()
            textLayer.string = caption.text
            textLayer.font = font
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = NSColor(hex: style.textColor).cgColor

            // Background
            if style.backgroundOpacity > 0 {
                let bgColor = NSColor(hex: style.backgroundColor).withAlphaComponent(style.backgroundOpacity)
                textLayer.backgroundColor = bgColor.cgColor
                textLayer.cornerRadius = fontSize * 0.2
            }

            // Shadow
            if style.shadow {
                textLayer.shadowColor = NSColor.black.cgColor
                textLayer.shadowOffset = CoreFoundation.CGSize(width: 0, height: -1)
                textLayer.shadowRadius = 2
                textLayer.shadowOpacity = 0.5
            }

            // Alignment
            let xPos: CGFloat
            switch style.horizontalAlignment {
            case 0.0: // Left
                textLayer.alignmentMode = .left
                xPos = CGFloat(renderSize.width) * (1.0 - style.maxLineWidth) / 2.0
            case 1.0: // Right
                textLayer.alignmentMode = .right
                xPos = CGFloat(renderSize.width) * (1.0 + style.maxLineWidth) / 2.0
            default: // Center (0.5)
                textLayer.alignmentMode = .center
                xPos = CGFloat(renderSize.width) * 0.5
            }

            // Wrap text if needed
            let wrappedText = wrapText(caption.text, font: font, maxWidth: maxLineWidth)
            textLayer.string = wrappedText

            // Calculate text size
            let textSize = (wrappedText as NSString).size(withAttributes: [.font: font])

            // Position text
            let textX = xPos - textSize.width / 2.0
            let textY = yPos - textSize.height
            textLayer.frame = CoreFoundation.CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            // Create fade-in and fade-out animations
            textLayer.opacity = 0.0

            // Fade in animation
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.duration = 0.2 // 200ms fade-in
            fadeIn.beginTime = startTime.seconds
            fadeIn.fillMode = .forwards

            // Fade out animation
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = 0.2 // 200ms fade-out
            fadeOut.beginTime = endTime.seconds - 0.2
            fadeOut.fillMode = .forwards

            // Add animations
            textLayer.add(fadeIn, forKey: "fadeIn_\(caption.id)")
            textLayer.add(fadeOut, forKey: "fadeOut_\(caption.id)")

            // Set final opacity for after animations
            DispatchQueue.main.asyncAfter(deadline: .now() + endTime.seconds) {
                textLayer.opacity = 0.0
            }

            captionLayer.addSublayer(textLayer)
        }

        // Create animation tool
        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        logger.debug("Caption layer created with \(captions.count) captions")

        return animationTool
    }

    /// Wrap text to fit within max width
    private func wrapText(_ text: String, font: NSFont, maxWidth: CGFloat) -> NSString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        var currentRange = CFRange(location: 0, length: attributedString.length)
        var lines: [String] = []

        while currentRange.length > 0 {
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                currentRange,
                nil,
                CoreFoundation.CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
                nil
            )

            let path = CGPath(rect: CoreFoundation.CGRect(origin: .zero, size: suggestedSize), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

            let lineRange = CTFrameGetVisibleStringRange(frame)
            let nsRange = NSRange(location: lineRange.location, length: lineRange.length)
            let lineText = attributedString.attributedSubstring(from: nsRange).string
            lines.append(lineText)

            currentRange.location += lineRange.length
            currentRange.length -= lineRange.length
        }

        return lines.joined(separator: "\n") as NSString
    }

    /// Validate that all source files exist
    private func validateSourceFiles(for project: Project, projectId: ProjectId) async throws {
        let projectDirectory = getProjectDirectory(for: projectId)
        logger.debug("Validating source files in: \(projectDirectory.path)")

        // Check screen file
        let screenPath = projectDirectory.appendingPathComponent(project.sources.screen.path)
        guard fileManager.fileExists(atPath: screenPath.path) else {
            logger.error("Screen file not found: \(project.sources.screen.path)")
            throw ExportError.sourceFileNotFound(project.sources.screen.path)
        }
        logger.debug("Screen file validated: \(project.sources.screen.path)")

        // Check camera file if present
        if let camera = project.sources.camera {
            let cameraPath = projectDirectory.appendingPathComponent(camera.path)
            guard fileManager.fileExists(atPath: cameraPath.path) else {
                logger.error("Camera file not found: \(camera.path)")
                throw ExportError.sourceFileNotFound(camera.path)
            }
            logger.debug("Camera file validated: \(camera.path)")
        }

        // Check audio files if present
        if let audio = project.sources.audio {
            if let systemAudio = audio.system {
                let systemAudioPath = projectDirectory.appendingPathComponent(systemAudio.path)
                guard fileManager.fileExists(atPath: systemAudioPath.path) else {
                    logger.error("System audio file not found: \(systemAudio.path)")
                    throw ExportError.sourceFileNotFound(systemAudio.path)
                }
                logger.debug("System audio file validated: \(systemAudio.path)")
            }

            if let micAudio = audio.mic {
                let micAudioPath = projectDirectory.appendingPathComponent(micAudio.path)
                guard fileManager.fileExists(atPath: micAudioPath.path) else {
                    logger.error("Mic audio file not found: \(micAudio.path)")
                    throw ExportError.sourceFileNotFound(micAudio.path)
                }
                logger.debug("Mic audio file validated: \(micAudio.path)")
            }
        }

        logger.info("All source files validated successfully")
    }

    /// Get project directory for a given project ID
    private func getProjectDirectory(for projectId: ProjectId) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDirectory = appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true)
        return baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
    }

    /// Calculate downscale transform from source to output size
    private func calculateDownscaleTransform(
        from sourceSize: CoreFoundation.CGSize,
        to outputSize: CoreFoundation.CGSize,
        contentMode: String
    ) -> CGAffineTransform {
        let sourceAspect = sourceSize.width / sourceSize.height
        let outputAspect = outputSize.width / outputSize.height

        var scale: CoreFoundation.CGFloat
        var translate = CGAffineTransform.identity

        if contentMode == "fit" {
            // Letterbox/pillarbox - fit entire source within output
            if sourceAspect > outputAspect {
                // Source is wider - scale to fit width
                scale = outputSize.width / sourceSize.width
                let scaledHeight = sourceSize.height * scale
                let yOffset = (outputSize.height - scaledHeight) / 2
                translate = CGAffineTransform(translationX: 0, y: yOffset)
            } else {
                // Source is taller - scale to fit height
                scale = outputSize.height / sourceSize.height
                let scaledWidth = sourceSize.width * scale
                let xOffset = (outputSize.width - scaledWidth) / 2
                translate = CGAffineTransform(translationX: xOffset, y: 0)
            }
        } else {
            // Fill - crop to fill output
            if sourceAspect > outputAspect {
                // Source is wider - scale to fit height (crop sides)
                scale = outputSize.height / sourceSize.height
                let scaledWidth = sourceSize.width * scale
                let xOffset = (outputSize.width - scaledWidth) / 2
                translate = CGAffineTransform(translationX: xOffset, y: 0)
            } else {
                // Source is taller - scale to fit width (crop top/bottom)
                scale = outputSize.width / sourceSize.width
                let scaledHeight = sourceSize.height * scale
                let yOffset = (outputSize.height - scaledHeight) / 2
                translate = CGAffineTransform(translationX: 0, y: yOffset)
            }
        }

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: CGFloat(scale), y: CGFloat(scale))
        transform = transform.concatenating(translate)

        return transform
    }

    /// Apply zoom transforms to layer instruction based on zoom plan keyframes
    /// - Parameters:
    ///   - layerInstruction: Layer instruction to apply transforms to
    ///   - zoomPlan: Zoom plan with keyframes
    ///   - baseTransform: Base transform (downscale, layout, etc.)
    ///   - sourceSize: Source video size
    ///   - renderSize: Output render size
    ///   - compositionDuration: Total composition duration
    /// - Throws: ExportError if transform application fails
    private func applyZoomTransforms(
        to layerInstruction: AVMutableVideoCompositionLayerInstruction,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        baseTransform: CGAffineTransform,
        sourceSize: CoreFoundation.CGSize,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws {
        guard !zoomPlan.keyframes.isEmpty else {
            // No keyframes, just apply base transform
            layerInstruction.setTransform(baseTransform, at: .zero)
            return
        }

        // Apply transform at each keyframe
        for keyframe in zoomPlan.keyframes {
            let keyframeTime = CMTime(seconds: keyframe.timestamp, preferredTimescale: 600)

            // Calculate zoom transform
            let zoomTransform = calculateZoomTransform(
                zoomLevel: keyframe.zoomLevel,
                focusX: keyframe.focusX,
                focusY: keyframe.focusY,
                baseTransform: baseTransform,
                sourceSize: sourceSize,
                renderSize: renderSize
            )

            layerInstruction.setTransform(zoomTransform, at: keyframeTime)
        }

        // Ensure first keyframe is applied at time zero
        if let firstKeyframe = zoomPlan.keyframes.first {
            let firstTransform = calculateZoomTransform(
                zoomLevel: firstKeyframe.zoomLevel,
                focusX: firstKeyframe.focusX,
                focusY: firstKeyframe.focusY,
                baseTransform: baseTransform,
                sourceSize: sourceSize,
                renderSize: renderSize
            )
            layerInstruction.setTransform(firstTransform, at: .zero)
        }
    }

    /// Calculate zoom transform for a specific zoom level and focus point
    /// - Parameters:
    ///   - zoomLevel: Zoom level (1.0 = no zoom, 2.0 = 2x zoom)
    ///   - focusX: Focus point X (normalized 0.0-1.0)
    ///   - focusY: Focus point Y (normalized 0.0-1.0)
    ///   - baseTransform: Base transform to apply zoom on top of
    ///   - sourceSize: Source video size
    ///   - renderSize: Output render size
    /// - Returns: Combined transform with zoom applied
    private func calculateZoomTransform(
        zoomLevel: Double,
        focusX: Double,
        focusY: Double,
        baseTransform: CGAffineTransform,
        sourceSize: CoreFoundation.CGSize,
        renderSize: CoreFoundation.CGSize
    ) -> CGAffineTransform {
        // Only apply zoom if zoom level is significant (> 1.01)
        guard zoomLevel > 1.01 else {
            return baseTransform
        }

        // Calculate focus point in render coordinates
        let focusPointRender = CGPoint(
            x: CGFloat(focusX) * renderSize.width,
            y: CGFloat(focusY) * renderSize.height
        )

        // Create zoom transform
        // 1. Translate to focus point
        let translateToFocus = CGAffineTransform(translationX: focusPointRender.x, y: focusPointRender.y)

        // 2. Scale by zoom level
        let scale = CGAffineTransform(scaleX: CGFloat(zoomLevel), y: CGFloat(zoomLevel))

        // 3. Translate back from focus point
        let translateFromFocus = CGAffineTransform(translationX: -focusPointRender.x, y: -focusPointRender.y)

        // Combine transforms: base -> translate to focus -> scale -> translate back
        var zoomTransform = baseTransform
        zoomTransform = zoomTransform.concatenating(translateToFocus)
        zoomTransform = zoomTransform.concatenating(scale)
        zoomTransform = zoomTransform.concatenating(translateFromFocus)

        return zoomTransform
    }
}

// MARK: - Export Preset

/// Export preset configuration
public struct ExportPreset: Equatable, Sendable {
    /// Preset identifier
    public let id: String
    /// Human-readable name
    public let name: String
    /// Output configuration
    public let output: OutputConfiguration
    /// Export options
    public let options: PresetOptions

    /// Output configuration
    public struct OutputConfiguration: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let fps: Int
        public let codec: String
        public let bitrateMbps: Double
        public let audioBitrateKbps: Int
    }

    /// Preset options
    public struct PresetOptions: Equatable, Sendable {
        public let burnCaptions: Bool
        public let includeCursorHighlight: Bool
    }

    /// Web 1080p H.264 preset (default)
    public static let web1080h264 = ExportPreset(
        id: "web_1080_h264",
        name: "Web 1080p (H.264)",
        output: OutputConfiguration(
            width: 1920,
            height: 1080,
            fps: 60,
            codec: "h264",
            bitrateMbps: 8.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// High-quality 1080p HEVC preset
    public static let high1080hevc = ExportPreset(
        id: "high_1080_hevc",
        name: "High 1080p (HEVC)",
        output: OutputConfiguration(
            width: 1920,
            height: 1080,
            fps: 60,
            codec: "hevc",
            bitrateMbps: 12.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// Portrait 9:16 1080p H.264 preset
    public static let portrait1080h264 = ExportPreset(
        id: "portrait_1080_h264",
        name: "Portrait 1080p (H.264)",
        output: OutputConfiguration(
            width: 1080,
            height: 1920,
            fps: 60,
            codec: "h264",
            bitrateMbps: 8.0,
            audioBitrateKbps: 192
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: true
        )
    )

    /// Animated GIF preset (for short clips and social media)
    public static let animatedGIF = ExportPreset(
        id: "animated_gif",
        name: "Animated GIF",
        output: OutputConfiguration(
            width: 800,
            height: 600,
            fps: 15,
            codec: "gif",
            bitrateMbps: 0,
            audioBitrateKbps: 0
        ),
        options: PresetOptions(
            burnCaptions: false,
            includeCursorHighlight: false
        )
    )
}

// MARK: - Export Options

/// Additional export options
public struct ExportOptions: Equatable, Sendable {
    /// Whether to burn captions into the video
    public let burnCaptions: Bool
    /// Whether to include cursor highlight overlay
    public let includeCursorHighlight: Bool
    /// Custom output filename (optional)
    public let outputFilename: String?
    /// GIF-specific options (for animated GIF exports)
    public let gifOptions: GIFExportOptions?
    /// Whether to apply zoom during export
    public let applyZoom: Bool
    /// Zoom plan to use for export (optional, will be loaded from project if not provided)
    public let zoomPlan: ZoomPlanGenerator.ZoomPlan?

    public init(
        burnCaptions: Bool = false,
        includeCursorHighlight: Bool = true,
        outputFilename: String? = nil,
        gifOptions: GIFExportOptions? = nil,
        applyZoom: Bool = true,
        zoomPlan: ZoomPlanGenerator.ZoomPlan? = nil
    ) {
        self.burnCaptions = burnCaptions
        self.includeCursorHighlight = includeCursorHighlight
        self.outputFilename = outputFilename
        self.gifOptions = gifOptions
        self.applyZoom = applyZoom
        self.zoomPlan = zoomPlan
    }

    public static let `default` = ExportOptions()

    /// Export options with zoom disabled
    public static let noZoom = ExportOptions(applyZoom: false)
}

// MARK: - GIF Export Options

/// Options specific to GIF export
public struct GIFExportOptions: Equatable, Sendable {
    /// Quality of the GIF (0.0 - 1.0, higher is better)
    public let quality: Double
    /// Number of times to loop the GIF (0 = infinite)
    public let loopCount: Int
    /// Maximum width/height (maintains aspect ratio)
    public let maxSize: Int?
    /// Frame rate for the GIF (overrides preset if specified)
    public let frameRate: Int?
    /// Whether to dither the GIF for better quality
    public let dither: Bool

    public init(
        quality: Double = 0.8,
        loopCount: Int = 0,
        maxSize: Int? = nil,
        frameRate: Int? = nil,
        dither: Bool = true
    ) {
        // Validate quality range
        self.quality = max(0.0, min(1.0, quality))
        self.loopCount = max(0, loopCount)
        self.maxSize = maxSize
        self.frameRate = frameRate
        self.dither = dither
    }

    public static let `default` = GIFExportOptions()

    /// High-quality GIF options (larger file size)
    public static let highQuality = GIFExportOptions(
        quality: 0.95,
        loopCount: 0,
        maxSize: nil,
        frameRate: nil,
        dither: true
    )

    /// Low-quality GIF options (smaller file size)
    public static let lowQuality = GIFExportOptions(
        quality: 0.5,
        loopCount: 0,
        maxSize: 600,
        frameRate: 10,
        dither: false
    )
}

// MARK: - Export Errors

/// Export engine errors
public enum ExportError: Error, Equatable, Sendable {
    case noSegments
    case sourceFileNotFound(String)
    case assetNotReadable(String)
    case compositionFailed(String)
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(String)
    case outputFileEmpty
    case insufficientDiskSpace
    case audioSyncDrift(TimeInterval)

    public var localizedDescription: String {
        switch self {
        case .noSegments:
            return "Project has no timeline segments to export"
        case .sourceFileNotFound(let path):
            return "Source file not found: \(path)"
        case .assetNotReadable(let asset):
            return "Asset not readable: \(asset)"
        case .compositionFailed(let reason):
            return "Failed to create composition: \(reason)"
        case .noVideoTrack:
            return "No video track found in source asset"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .outputFileEmpty:
            return "Output file is empty or was not created"
        case .insufficientDiskSpace:
            return "Insufficient disk space for export"
        case .audioSyncDrift(let drift):
            return "Audio sync drift detected: \(drift * 1000)ms"
        }
    }
}

// MARK: - Export Result

/// Export result information
public struct ExportResult: Sendable {
    /// Output file URL
    public let outputURL: URL
    /// Output file size in bytes
    public let fileSize: UInt64
    /// Output duration in seconds
    public let duration: TimeInterval
    /// Preset used for export
    public let preset: ExportPreset
}

// MARK: - NSColor Extension

/// Extension for creating NSColor from hex strings
extension NSColor {
    /// Create NSColor from hex string (e.g., "#FFFFFF" or "FFFFFF")
    /// - Parameter hex: Hex color string
    /// - Returns: NSColor instance
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }

    /// Convert NSColor to CGColor
    var cgColor: CGColor {
        return self.cgColor
    }
}
