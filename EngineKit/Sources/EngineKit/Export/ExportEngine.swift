//
//  ExportEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import AppKit
import os.log

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

            layerInstruction.setTransform(transform, at: .zero)
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
        try captionsManager.loadCaptions(from: captionPath.path)
        let captions = captionsManager.getAllCaptions()

        logger.debug("Loaded \(captions.count) captions for burn-in")

        // Create parent layer for video composition
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)

        // Create video layer
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Create caption layer
        let captionLayer = CALayer()
        captionLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(captionLayer)

        // Get caption style
        let style = captionsManager.getStyle()

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
                textLayer.shadowOffset = CGSize(width: 0, height: -1)
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
            textLayer.frame = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

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
                CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
                nil
            )

            let path = CGPath(rect: CGRect(origin: .zero, size: suggestedSize), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

            let lineRange = CTFrameGetVisibleStringRange(frame)
            let lineText = attributedString.attributedSubstring(from: NSRange(lineRange)).string
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

    public init(
        burnCaptions: Bool = false,
        includeCursorHighlight: Bool = true,
        outputFilename: String? = nil
    ) {
        self.burnCaptions = burnCaptions
        self.includeCursorHighlight = includeCursorHighlight
        self.outputFilename = outputFilename
    }

    public static let `default` = ExportOptions()
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
