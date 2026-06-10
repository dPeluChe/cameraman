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
    /// Current export stage per job
    var exportStages: [JobId: ExportStage] = [:]
    /// Last logged integer percent per job — used to dedup spammy progress events
    /// from AVAssetExportSession which fires the same % multiple times in a row.
    var lastLoggedProgress: [JobId: Int] = [:]

    /// Initialize ExportEngine
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

    /// Initialize export stage tracking for a job
    func initializeExportStages(for jobId: JobId, project: Project, preset: ExportPreset) {
        exportStages[jobId] = .validation
        logger.info("Initialized export stages for job \(jobId.uuidString): \(preset.name)")
    }

    /// Update export stage with logging. Progress messages are deduped: only emit
    /// when the integer percentage changes (otherwise AVAssetExportSession fires
    /// the same value many times in a row and floods the console).
    func updateExportStage(jobId: JobId, stage: ExportStage, progress: Double) async {
        exportStages[jobId] = stage
        let percent = Int(progress * 100)
        if lastLoggedProgress[jobId] != percent {
            lastLoggedProgress[jobId] = percent
            logger.info("Export progress: \(stage.description) (\(percent)%)")
        }
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
        logger.info("Cleaning up export resources for job: \(jobId.uuidString)")
        exportStages.removeValue(forKey: jobId)
        lastLoggedProgress.removeValue(forKey: jobId)
    }

    // MARK: - Public API

    /// Start an export job for a project
    public func export(
        projectId: ProjectId,
        preset: ExportPreset = .web1080h264,
        options: ExportOptions = .default
    ) async throws -> JobId {
        logger.info("Starting export for project: \(projectId.uuidString), preset: \(preset.id)")

        let project = try await projectStore.loadProject(projectId: projectId)
        logger.debug("Loaded project '\(project.name)' with \(project.timeline.primaryTrack?.clips.count ?? 0) primary clips")

        // Imported-only projects are exportable: any track with clips counts.
        guard project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) else {
            logger.error("Export failed: project has no timeline clips")
            throw ExportError.noSegments
        }

        try await validateSourceFiles(for: project, projectId: projectId)
        logger.debug("All source files validated successfully")

        let jobId = await jobQueue.createJob(type: .export, projectId: projectId)
        logger.info("Created export job: \(jobId.uuidString)")

        initializeExportStages(for: jobId, project: project, preset: preset)

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
    public func exportGIF(
        projectId: ProjectId,
        preset: ExportPreset = .animatedGIF,
        options: ExportOptions = .default
    ) async throws -> JobId {
        logger.info("Starting GIF export for project: \(projectId.uuidString), preset: \(preset.id)")

        let project = try await projectStore.loadProject(projectId: projectId)
        logger.debug("Loaded project '\(project.name)' with \(project.timeline.primaryTrack?.clips.count ?? 0) primary clips")

        guard let primaryTrack = project.timeline.primaryTrack, !primaryTrack.clips.isEmpty else {
            logger.error("GIF export failed: project has no timeline clips")
            throw ExportError.noSegments
        }

        try await validateSourceFiles(for: project, projectId: projectId)
        logger.debug("All source files validated successfully")

        let jobId = await jobQueue.createJob(type: .export, projectId: projectId)
        logger.info("Created GIF export job: \(jobId.uuidString)")

        initializeExportStages(for: jobId, project: project, preset: preset)

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
    public func getJobQueue() -> JobQueue {
        return self.jobQueue
    }
}
