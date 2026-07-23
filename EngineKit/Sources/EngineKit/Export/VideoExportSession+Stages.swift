//
//  VideoExportSession+Stages.swift
//  EngineKit
//
//  Extracted from VideoExportSession.swift (Phase 1 refactor, v0.5.1).
//  Individual pipeline stages: prepare output, validate assets, build composition,
//  configure export session, run export, verify output.
//

import Foundation
import AVFoundation
import AppKit

extension ExportEngine {
    /// Stage 1: Resolve output URL inside the project's `renders/` directory and
    /// remove any existing file at that path so AVAssetExportSession can write fresh.
    func prepareExportOutputURL(in projectDirectory: URL, options: ExportOptions) throws -> URL {
        let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        logger.debug("Created renders directory: \(outputDirectory.path)")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let outputFilename = options.outputFilename ?? "export_\(timestamp).mp4"
        let outputURL = outputDirectory.appendingPathComponent(outputFilename)

        logger.info("Output file: \(outputFilename)")
        logger.info("Output path: \(outputURL.path)")

        if fileManager.fileExists(atPath: outputURL.path) {
            logger.debug("Output file already exists, deleting: \(outputURL.path)")
            do {
                try fileManager.removeItem(at: outputURL)
                logger.debug("Deleted existing output file")
            } catch {
                logger.error("Failed to delete existing output file: \(error.localizedDescription)")
            }
        }

        return outputURL
    }

    /// Stage 2: Fail fast if the primary screen recording is unreadable — skipping this
    /// check lets AVAssetExportSession fail much later with an opaque error.
    func validatePrimaryScreenAsset(
        projectDirectory: URL,
        primarySources: Project.Sources
    ) async throws {
        let primaryScreenPath = primarySources.screen.path
        let primaryScreenAsset = AVAsset(url: projectDirectory.appendingPathComponent(primaryScreenPath))

        let isScreenReadable = try await primaryScreenAsset.load(.isReadable)
        guard isScreenReadable else {
            logger.error("Primary screen asset is not readable")
            throw ExportError.assetNotReadable("screen")
        }
        logger.debug("Primary screen asset validated successfully")
    }

    /// Stage 3: Build the AVComposition from the project timeline.
    func buildExportComposition(
        project: Project,
        projectDirectory: URL,
        jobId: JobId
    ) async throws -> CompositionBuilder.Result {
        logger.debug("Building video composition from timeline tracks")

        let builder = CompositionBuilder(fileManager: fileManager)
        let resolver = CompositionBuilder.SourceResolver(projectDirectory: projectDirectory)

        let result = try await builder.buildComposition(
            project: project,
            resolver: resolver,
            resolveSources: { [self] takeId in
                self.resolveSources(for: takeId, in: project)
            },
            cancellationCheck: { [self] in
                try await self.checkCancellation(jobId: jobId)
            }
        )

        logger.debug("Composition built: \(result.composition.duration.seconds)s, camera: \(result.cameraTrack != nil), systemAudio: \(result.systemAudioTrack != nil), micAudio: \(result.micAudioTrack != nil)")
        return result
    }

    /// Stage 5: Wire the composition, video composition, overlays, and audio mix into an
    /// AVAssetExportSession configured for the given preset and output URL.
    func configureExportSession(
        composition: AVComposition,
        videoComposition: AVMutableVideoComposition,
        outputURL: URL,
        preset: ExportPreset,
        project: Project,
        projectId: ProjectId,
        compositionResult: CompositionBuilder.Result,
        options: ExportOptions
    ) async throws -> AVAssetExportSession {
        logger.debug("Configuring export session")

        // Honor the preset's codec — HEVC presets exported H.264 before because
        // the session was always created with HighestQuality.
        let sessionPreset = preset.output.codec == "hevc"
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: sessionPreset
        ) else {
            logger.error("Failed to create export session")
            throw ExportError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // The preset's bitrate was decorative before (HighestQuality ignored it →
        // a 951MB 8-minute export). AVAssetExportSession has no direct bitrate
        // knob; fileLengthLimit makes it hit the preset's target data rate.
        if preset.output.bitrateMbps > 0 {
            let durationSeconds = composition.duration.seconds
            let limit = preset.targetFileSizeBytes(
                duration: durationSeconds,
                qualityMultiplier: options.qualityMultiplier
            )
            exportSession.fileLengthLimit = limit
            logger.debug("File length limit: \(limit / 1_000_000)MB for \(Int(durationSeconds))s at quality x\(options.qualityMultiplier)")
        }

        logger.debug("Export output URL: \(outputURL.path)")
        logger.debug("Export file type: \(exportSession.outputFileType?.rawValue ?? "unknown")")

        verifyOutputDirectoryWritable(outputURL: outputURL)

        // Burn-in overlays: captions, images, shapes
        let hasCaptions = options.burnCaptions || preset.options.burnCaptions
        let hasImageOverlays = !project.mediaItems.filter { $0.type == .image }.isEmpty
        let hasShapeOverlays = !project.overlays.isEmpty || !project.subtitles.isEmpty

        if hasCaptions || hasImageOverlays || hasShapeOverlays || options.includeCameramanWatermark {
            logger.debug("Creating combined overlay layer (captions: \(hasCaptions), images: \(hasImageOverlays), shapes: \(hasShapeOverlays), watermark: \(options.includeCameramanWatermark))")
            do {
                let combinedTool = try await createCombinedOverlayLayer(
                    for: project,
                    projectId: projectId,
                    renderSize: videoComposition.renderSize,
                    compositionDuration: composition.duration,
                    burnCaptions: hasCaptions,
                    includeCameramanWatermark: options.includeCameramanWatermark
                )
                if let tool = combinedTool {
                    videoComposition.animationTool = tool
                }
                logger.debug("Combined overlay layer applied successfully")
            } catch {
                logger.error("Failed to apply combined overlay layer: \(error.localizedDescription)")
            }
        }

        // Always assign videoComposition (carries compositor, render size, per-segment instructions).
        exportSession.videoComposition = videoComposition

        // Per-track mute/volume mix.
        if let audioMuteState = options.audioMuteState {
            let audioMix = AudioMixBuilder.buildAudioMix(
                compositionResult: compositionResult,
                muteState: audioMuteState,
                segments: project.timeline.segments,
                audioAdjustments: project.audioAdjustmentSpecs
            )
            exportSession.audioMix = audioMix
        }

        logger.debug("Export session configured successfully")
        return exportSession
    }

    /// Stage 6: Run the export and stream progress updates back to the job queue.
    func runExportSession(_ exportSession: AVAssetExportSession, jobId: JobId) async {
        logger.debug("Starting AVFoundation export")

        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                let progress = Float(exportSession.progress)
                let overallProgress = Double(progress * 0.35 + 0.6) // Map to 0.6-0.95 range
                await updateExportStage(
                    jobId: jobId,
                    stage: .exporting(progress: Double(progress)),
                    progress: overallProgress
                )
            }
        }

        await exportSession.export()
        progressTask.cancel()

        logger.debug("AVFoundation export completed with status: \(exportSession.status.rawValue)")
    }

    /// Stage 7: Fail if the export session did not complete or the output is empty.
    func verifyExportOutput(
        _ exportSession: AVAssetExportSession,
        outputURL: URL
    ) throws -> UInt64 {
        logger.debug("Verifying output file")

        if fileManager.fileExists(atPath: outputURL.path) {
            logger.debug("Output file exists immediately after export")
        } else {
            logger.warning("Output file does NOT exist immediately after export")
        }

        guard exportSession.status == .completed else {
            logExportSessionFailure(exportSession, outputURL: outputURL)
            throw ExportError.exportFailed(
                exportSession.error?.localizedDescription
                    ?? "Export failed with status: \(exportSession.status.rawValue)"
            )
        }

        let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes?[.size] as? UInt64 ?? 0

        guard fileSize > 0 else {
            logger.error("Output file is empty")
            throw ExportError.outputFileEmpty
        }

        logger.info("Output file verified: \(fileSize) bytes")
        return fileSize
    }

    // MARK: - Private helpers

    private func verifyOutputDirectoryWritable(outputURL: URL) {
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
    }

    private func logExportSessionFailure(
        _ exportSession: AVAssetExportSession,
        outputURL: URL
    ) {
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
            let nsError = error as NSError
            logger.error("Export error userInfo: \(nsError.userInfo)")
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            logger.warning("Output file exists despite export failure: \(outputURL.path)")
        } else {
            logger.warning("Output file does not exist: \(outputURL.path)")
        }
    }
}
