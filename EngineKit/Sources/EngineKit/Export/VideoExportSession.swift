//
//  VideoExportSession.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import AppKit

extension ExportEngine {
    /// Perform the actual export work
    func performExport(
        jobId: JobId,
        projectId: ProjectId,
        project: Project,
        preset: ExportPreset,
        options: ExportOptions
    ) async {
        let startTime = Date()
        logger.debug("Starting export performance for job: \(jobId.uuidString)")

        // Ensure we have at least some sources to work with for global settings (like resolution)
        guard let primarySources = project.primarySources else {
            let error = ExportError.mediaFileNotFound("No sources found in project")
            logExportError(jobId: jobId, error: error, stage: .validation)
            let jobError = Job.JobError(
                code: "EXPORT_FAILED",
                message: error.localizedDescription,
                details: ["original_error": .string(String(describing: error))],
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await cleanupExport(jobId: jobId)
            return
        }

        do {
            let projectDirectory = try await projectStore.projectDirectoryURL(for: projectId)
            let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)

            // Create renders directory if it doesn't exist
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            logger.debug("Created renders directory: \(outputDirectory.path)")

            // Generate output filename with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputFilename = options.outputFilename ?? "export_\(timestamp).mp4"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            logger.info("Output file: \(outputFilename)")
            logger.info("Output path: \(outputURL.path)")

            // Delete output file if it already exists
            if fileManager.fileExists(atPath: outputURL.path) {
                logger.debug("Output file already exists, deleting: \(outputURL.path)")
                do {
                    try fileManager.removeItem(at: outputURL)
                    logger.debug("Deleted existing output file")
                } catch {
                    logger.error("Failed to delete existing output file: \(error.localizedDescription)")
                }
            }

            logger.info("Output file: \(outputFilename)")

            // Stage 1: Validation (0.0 - 0.1)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .validation, progress: 0.02)
            logger.debug("Validating project segments")
            logger.debug("Project has \(project.timeline.segments.count) segments")

            // Stage 2: Load and validate source assets (0.1 - 0.2)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .assetLoading, progress: 0.1)

            // Pre-validate primary screen asset readability
            let primaryScreenPath = primarySources.screen.path
            let primaryScreenAsset = AVAsset(url: projectDirectory.appendingPathComponent(primaryScreenPath))

            let isScreenReadable = try await primaryScreenAsset.load(.isReadable)
            guard isScreenReadable else {
                logger.error("Primary screen asset is not readable")
                throw ExportError.assetNotReadable("screen")
            }
            logger.debug("Primary screen asset validated successfully")

            // Check for cancellation after asset loading
            try await checkCancellation(jobId: jobId)

            // Stage 3: Create composition with trims/cuts applied (0.2 - 0.4)
            await updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.25)
            logger.debug("Building video composition from timeline segments")

            let builder = CompositionBuilder(fileManager: fileManager)
            let resolver = CompositionBuilder.SourceResolver(projectDirectory: projectDirectory)

            let compositionResult = try await builder.buildComposition(
                project: project,
                resolver: resolver,
                resolveSources: { [self] segment in
                    self.resolveSources(for: segment.takeId, in: project)
                },
                cancellationCheck: { [self] in
                    try await self.checkCancellation(jobId: jobId)
                }
            )

            let composition = compositionResult.composition
            let videoTrack = compositionResult.videoTrack
            let cameraTrack = compositionResult.cameraTrack

            logger.debug("Composition built: \(composition.duration.seconds)s, camera: \(cameraTrack != nil), systemAudio: \(compositionResult.systemAudioTrack != nil), micAudio: \(compositionResult.micAudioTrack != nil)")

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
            // NOTE: We assume all clips have the same resolution as primary sources for now
            let sourceSize = CoreFoundation.CGSize(
                width: CGFloat(primarySources.screen.size.w),
                height: CGFloat(primarySources.screen.size.h)
            )

            logger.debug("Source size: \(primarySources.screen.size.w)x\(primarySources.screen.size.h)")

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

            // Add camera layer instruction if camera track exists
            if let cameraTrack = cameraTrack, let cameraPosition = project.canvas.layout.camera {
                logger.debug("Adding camera overlay layer instruction")

                let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)

                // Use actual track dimensions for correct transform calculation
                let trackSize = cameraTrack.naturalSize
                let cameraSourceSize = CoreFoundation.CGSize(
                    width: trackSize.width > 0 ? trackSize.width : CGFloat(primarySources.camera?.size.w ?? 1280),
                    height: trackSize.height > 0 ? trackSize.height : CGFloat(primarySources.camera?.size.h ?? 720)
                )
                logger.debug("Camera actual size: \(Int(cameraSourceSize.width))x\(Int(cameraSourceSize.height))")

                let cameraTransform = calculateCameraOverlayTransform(
                    cameraPosition: cameraPosition,
                    cameraSourceSize: cameraSourceSize,
                    renderSize: videoComposition.renderSize
                )

                cameraLayerInstruction.setTransform(cameraTransform, at: .zero)

                // Camera first = on top (frontmost in AVFoundation layer order)
                instruction.layerInstructions = [cameraLayerInstruction, layerInstruction]
                logger.debug("Camera overlay added to composition")
            } else {
                instruction.layerInstructions = [layerInstruction]
            }

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
            exportSession.shouldOptimizeForNetworkUse = true

            logger.debug("Export output URL: \(outputURL.path)")
            logger.debug("Export file type: \(exportSession.outputFileType?.rawValue ?? "unknown")")

            // Check if output directory exists and is writable
            let outputDir = outputURL.deletingLastPathComponent()
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: outputDir.path, isDirectory: &isDir) && isDir.boolValue {
                logger.debug("Output directory exists: \(outputDir.path)")
                if fileManager.isWritableFile(atPath: outputDir.path) {
                    logger.debug("Output directory is writable")
                } else {
                    logger.error("Output directory is not writable: \(outputDir.path)")
                }
            } else {
                logger.error("Output directory does not exist or is not a directory: \(outputDir.path)")
            }

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

            logger.debug("AVFoundation export completed with status: \(exportSession.status.rawValue)")

            // Check file existence immediately after export
            if fileManager.fileExists(atPath: outputURL.path) {
                logger.debug("Output file exists immediately after export")
            } else {
                logger.warning("Output file does NOT exist immediately after export")
            }

            // Stage 7: Verify output (0.95 - 1.0)
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .verification, progress: 0.97)
            logger.debug("Verifying output file")

            guard exportSession.status == .completed else {
                let statusDescription: String
                switch exportSession.status {
                case .unknown: statusDescription = "unknown"
                case .waiting: statusDescription = "waiting"
                case .exporting: statusDescription = "exporting"
                case .completed: statusDescription = "completed"
                case .failed: statusDescription = "failed"
                case .cancelled: statusDescription = "cancelled"
                @unknown default: statusDescription = "other (\(exportSession.status.rawValue))"
                }

                logger.error("Export session failed with status: \(statusDescription) (\(exportSession.status.rawValue))")

                if let error = exportSession.error {
                    logger.error("Export error domain: \(error._domain)")
                    logger.error("Export error code: \(error._code)")
                    logger.error("Export error: \(error.localizedDescription)")

                    // Try to get more error details
                    let nsError = error as NSError
                    if let userInfo = nsError.userInfo as? [String: Any] {
                        logger.error("Export error userInfo: \(userInfo)")
                    }
                }

                // Check if output file exists despite error
                if fileManager.fileExists(atPath: outputURL.path) {
                    logger.warning("Output file exists despite export failure: \(outputURL.path)")
                } else {
                    logger.warning("Output file does not exist: \(outputURL.path)")
                }

                throw ExportError.exportFailed(exportSession.error?.localizedDescription ?? "Export failed with status: \(statusDescription)")
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
            let currentStage = exportStages[jobId] ?? .validation
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

}
