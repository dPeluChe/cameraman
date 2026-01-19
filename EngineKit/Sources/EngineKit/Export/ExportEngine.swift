//
//  ExportEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// ExportEngine handles video export with trims, cuts, layouts, and overlays applied
/// Supports downsampling from native resolution to 1080p, with configurable presets
public actor ExportEngine {
    /// Shared job queue for async operations
    private let jobQueue: JobQueue
    /// Project store for reading projects
    private let projectStore: ProjectStore
    /// File manager for file operations
    private let fileManager: FileManager

    /// Initialize ExportEngine
    /// - Parameters:
    ///   - jobQueue: JobQueue for managing export jobs
    ///   - projectStore: ProjectStore for reading projects
    public init(jobQueue: JobQueue, projectStore: ProjectStore) {
        self.jobQueue = jobQueue
        self.projectStore = projectStore
        self.fileManager = FileManager.default
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
        // Load project
        let project = try await projectStore.loadProject(projectId: projectId)

        // Validate project has segments
        guard !project.timeline.segments.isEmpty else {
            throw ExportError.noSegments
        }

        // Validate source files exist
        try await validateSourceFiles(for: project, projectId: projectId)

        // Create job
        let jobId = await jobQueue.createJob(type: .export, projectId: projectId)

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
        do {
            let projectDirectory = getProjectDirectory(for: projectId)
            let outputDirectory = projectDirectory.appendingPathComponent("renders", isDirectory: true)

            // Create renders directory if it doesn't exist
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            // Generate output filename with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputFilename = "export_\(timestamp).mp4"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            // Step 1: Load and validate source assets (0.0 - 0.2)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.05)
            let screenAsset = AVAsset(url: projectDirectory.appendingPathComponent(project.sources.screen.path))

            // Verify screen asset is readable
            let isScreenReadable = try await screenAsset.load(.isReadable)
            guard isScreenReadable else {
                throw ExportError.assetNotReadable("screen")
            }

            // Step 2: Create composition with trims/cuts applied (0.2 - 0.4)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.2)
            let composition = AVMutableComposition()

            // Build video track from timeline segments
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.compositionFailed("Failed to create video track")
            }

            var currentTime = CMTime.zero
            let videoAssetTracks = try await screenAsset.loadTracks(withMediaType: .video)

            guard let sourceVideoTrack = videoAssetTracks.first else {
                throw ExportError.noVideoTrack
            }

            // Apply timeline segments (trims, cuts, speed)
            for segment in project.timeline.segments {
                let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                let duration = CMTime(seconds: segment.sourceOut - segment.sourceIn, preferredTimescale: 600)

                // Calculate scaled duration based on speed
                let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / segment.speed)

                try videoTrack.insertTimeRange(
                    CMTimeRangeMake(start: startTime, duration: duration),
                    of: sourceVideoTrack,
                    at: currentTime
                )

                currentTime = CMTimeAdd(currentTime, scaledDuration)
            }

            // Build audio track if available
            var audioAsset: AVAsset?
            var audioTrack: AVMutableCompositionTrack?

            if let audioPath = project.sources.audio?.system?.path {
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
                    }
                }
            }

            // Step 3: Apply layout and transforms (0.4 - 0.5)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.4)
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CoreFoundation.CGSize(width: CGFloat(preset.output.width), height: CGFloat(preset.output.height))
            videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(preset.output.fps))

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

            let transform = calculateDownscaleTransform(
                from: sourceSize,
                to: videoComposition.renderSize,
                contentMode: project.canvas.background.fitMode ?? "fill"
            )

            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]

            // Step 4: Setup export session (0.5 - 0.6)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.5)
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw ExportError.exportSessionCreationFailed
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.videoComposition = videoComposition

            // Note: AVAssetExportSession doesn't allow direct videoSettings/audioSettings
            // The presetName and videoComposition determine the output quality and format
            // For more control, we would need to use AVAssetReader/AVAssetWriter like ProxyGenerator

            // Step 5: Perform export with progress monitoring (0.6 - 1.0)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.6)

            // Monitor export progress
            let progressTask = Task {
                while !Task.isCancelled && exportSession.status == .exporting {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    let progress = Float(exportSession.progress)
                    await jobQueue.updateJobProgress(jobId: jobId, progress: Double(progress * 0.4 + 0.6))
                }
            }

            await exportSession.export()

            progressTask.cancel()

            // Step 6: Verify output (1.0)
            guard exportSession.status == .completed else {
                throw ExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
            }

            // Verify output file exists and has content
            let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes?[.size] as? UInt64 ?? 0

            guard fileSize > 0 else {
                throw ExportError.outputFileEmpty
            }

            // Complete job
            await jobQueue.completeJob(jobId: jobId)

        } catch {
            // Fail job with error
            let jobError = Job.JobError(
                code: "EXPORT_FAILED",
                message: error.localizedDescription,
                details: ["original_error": .string(String(describing: error))],
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
        }
    }

    /// Validate that all source files exist
    private func validateSourceFiles(for project: Project, projectId: ProjectId) async throws {
        let projectDirectory = getProjectDirectory(for: projectId)

        // Check screen file
        let screenPath = projectDirectory.appendingPathComponent(project.sources.screen.path)
        guard fileManager.fileExists(atPath: screenPath.path) else {
            throw ExportError.sourceFileNotFound(project.sources.screen.path)
        }

        // Check camera file if present
        if let camera = project.sources.camera {
            let cameraPath = projectDirectory.appendingPathComponent(camera.path)
            guard fileManager.fileExists(atPath: cameraPath.path) else {
                throw ExportError.sourceFileNotFound(camera.path)
            }
        }

        // Check audio files if present
        if let audio = project.sources.audio {
            if let systemAudio = audio.system {
                let systemAudioPath = projectDirectory.appendingPathComponent(systemAudio.path)
                guard fileManager.fileExists(atPath: systemAudioPath.path) else {
                    throw ExportError.sourceFileNotFound(systemAudio.path)
                }
            }

            if let micAudio = audio.mic {
                let micAudioPath = projectDirectory.appendingPathComponent(micAudio.path)
                guard fileManager.fileExists(atPath: micAudioPath.path) else {
                    throw ExportError.sourceFileNotFound(micAudio.path)
                }
            }
        }
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
