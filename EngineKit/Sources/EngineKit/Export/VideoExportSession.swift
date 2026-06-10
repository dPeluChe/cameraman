//
//  VideoExportSession.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//
//  Entry point for video export. The pipeline stages live in:
//    - VideoExportSession+Stages.swift       (prepare/validate/configure/run/verify)
//    - VideoExportSession+Composition.swift  (video composition construction)
//

import Foundation
import AVFoundation
import CoreGraphics

extension ExportEngine {
    /// Orchestrate the export pipeline. Each stage lives in a focused helper; this method
    /// wires them together, tracks progress, and maps errors to job-queue failures.
    func performExport(
        jobId: JobId,
        projectId: ProjectId,
        project: Project,
        preset: ExportPreset,
        options: ExportOptions
    ) async {
        let startTime = Date()
        logger.debug("Starting export performance for job: \(jobId.uuidString)")

        // Empty projects (imported clips only) have no recording sources —
        // synthesize screen metadata from the canvas so downstream transforms
        // use the right dimensions; the compositor renders the background where
        // the (empty) screen track has no frames.
        let primarySources = project.primarySources ?? Project.Sources(
            screen: Project.Sources.MediaTrack(
                path: "",
                fps: 60,
                size: Project.Sources.Size(w: project.canvas.format.w, h: project.canvas.format.h)
            )
        )

        do {
            let projectDirectory = try await projectStore.projectDirectoryURL(for: projectId)
            let outputURL = try prepareExportOutputURL(in: projectDirectory, options: options)

            // Stage 1: Validation
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .validation, progress: 0.02)
            logger.debug("Project has \(project.timeline.primaryTrack?.clips.count ?? 0) primary clips")

            // Stage 2: Load and validate source assets
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .assetLoading, progress: 0.1)
            if project.primarySources != nil {
                try await validatePrimaryScreenAsset(projectDirectory: projectDirectory, primarySources: primarySources)
            }

            // Stage 3: Build composition
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .compositionBuilding, progress: 0.25)
            let compositionResult = try await buildExportComposition(
                project: project,
                projectDirectory: projectDirectory,
                jobId: jobId
            )

            // Stage 4: Video composition setup
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .videoCompositionSetup, progress: 0.45)
            let videoComposition = try await buildExportVideoComposition(
                project: project,
                preset: preset,
                options: options,
                compositionResult: compositionResult,
                primarySources: primarySources
            )

            // Stage 5: Configure export session
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .exportSessionConfig, progress: 0.55)
            let exportSession = try await configureExportSession(
                composition: compositionResult.composition,
                videoComposition: videoComposition,
                outputURL: outputURL,
                preset: preset,
                project: project,
                projectId: projectId,
                compositionResult: compositionResult,
                options: options
            )

            // Stage 6: Run export
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .exportSessionConfig, progress: 0.6)
            await runExportSession(exportSession, jobId: jobId)

            // Stage 7: Verify output
            try await checkCancellation(jobId: jobId)
            await updateExportStage(jobId: jobId, stage: .verification, progress: 0.97)
            let fileSize = try verifyExportOutput(exportSession, outputURL: outputURL)

            // Stage 8: Cleanup
            await updateExportStage(jobId: jobId, stage: .cleanup, progress: 0.99)
            let result = ExportResult(
                outputURL: outputURL,
                fileSize: fileSize,
                duration: compositionResult.composition.duration.seconds,
                preset: preset
            )
            logExportSummary(jobId: jobId, result: result, duration: Date().timeIntervalSince(startTime))

            await jobQueue.completeJob(jobId: jobId)
            await cleanupExport(jobId: jobId)
        } catch {
            let currentStage = exportStages[jobId] ?? .validation
            await failExport(jobId: jobId, error: error, stage: currentStage)
        }
    }

    private func failExport(jobId: JobId, error: Error, stage: ExportStage) async {
        logExportError(jobId: jobId, error: error, stage: stage)
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
