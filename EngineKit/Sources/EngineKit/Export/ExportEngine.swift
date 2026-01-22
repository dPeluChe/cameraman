//
//  ExportEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import AppKit
import CoreGraphics
import os.log

/// ExportEngine handles video export with trims, cuts, layouts, and overlays applied
/// Supports downsampling from native resolution to 1080p, with configurable presets
/// Enhanced with structured logging, detailed progress tracking, and cancellation support
public actor ExportEngine {
    /// Shared job queue for async operations
    let jobQueue: JobQueue
    /// Project store for reading projects
    let projectStore: ProjectStore
    /// File manager for file operations
    let fileManager: FileManager
    /// Structured logging
    let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "ExportEngine")
    /// Export stage tracking for detailed progress
    var exportStages: [JobId: [ExportStage]] = [:]

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
    enum ExportStage {
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
    func initializeExportStages(for jobId: JobId, project: Project, preset: ExportPreset) {
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
    func updateExportStage(jobId: JobId, stage: ExportStage, progress: Double) async {
        exportStages[jobId]?.append(stage)

        // Log the stage change with structured data
        logger.debug("Export stage: \(stage.description) (progress: \(Int(progress * 100))%) jobId: \(jobId.uuidString)")

        // Update job progress
        await jobQueue.updateJobProgress(jobId: jobId, progress: progress)
    }

    /// Log export summary
    func logExportSummary(jobId: JobId, result: ExportResult, duration: TimeInterval) {
        logger.info("Export completed successfully - jobId: \(jobId.uuidString), outputFile: \(result.outputURL.lastPathComponent), fileSize: \(result.fileSize), duration: \(result.duration)s, preset: \(result.preset.id), exportTime: \(duration)s")
    }

    /// Log export error with structured details
    func logExportError(jobId: JobId, error: Error, stage: ExportStage) {
        logger.error("Export failed at stage: \(stage.description) - jobId: \(jobId.uuidString), stage: \(stage.description), error: \(error.localizedDescription), errorType: \(String(describing: type(of: error)))")
    }

    /// Check for cancellation and throw if needed
    func checkCancellation(jobId: JobId) async throws {
        if Task.isCancelled {
            logger.info("Export cancelled by user at job: \(jobId.uuidString)")
            await cleanupExport(jobId: jobId)
            throw ExportError.exportFailed("Export was cancelled")
        }
    }

    /// Cleanup export resources
    func cleanupExport(jobId: JobId) async {
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
}

// MARK: - Export Preset

/// Export preset configuration
public struct ExportPreset: Equatable, Hashable, Sendable {
    /// Preset identifier
    public let id: String
    /// Human-readable name
    public let name: String
    /// Output configuration
    public let output: OutputConfiguration
    /// Export options
    public let options: PresetOptions

    /// Output configuration
    public struct OutputConfiguration: Equatable, Hashable, Sendable {
        public let width: Int
        public let height: Int
        public let fps: Int
        public let codec: String
        public let bitrateMbps: Double
        public let audioBitrateKbps: Int
    }

    /// Preset options
    public struct PresetOptions: Equatable, Hashable, Sendable {
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
    case missingSourceFile(String)
    case sourceFileNotFound(String)
    case mediaFileNotFound(String)
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
        case .missingSourceFile(let message):
            return "Missing source file: \(message)"
        case .sourceFileNotFound(let path):
            return "Source file not found: \(path)"
        case .mediaFileNotFound(let path):
            return "Media file not found: \(path)"
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
