//
//  AIService.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// AIService provides AI-assisted editing features for video projects.
///
/// This service supports both local and cloud-based AI operations:
/// - Local: Silence detection, chapter suggestions from transcript (P1)
/// - Cloud: Background asset generation, frame-by-frame style transfer (P2, future)
///
/// The service is designed to be extensible and provider-agnostic.
/// All AI operations are async and job-based for progress tracking.
public actor AIService {
    /// Shared job queue for async operations
    let jobQueue: JobQueue
    /// Project store for reading/writing projects
    let projectStore: ProjectStore
    /// File manager for file operations
    let fileManager = FileManager.default
    /// Optional override for project directory base (useful for tests)
    let projectDirectoryOverride: URL?

    /// AI provider configuration
    var provider: AIProvider?

    /// Initialize AIService
    /// - Parameters:
    ///   - jobQueue: JobQueue for managing AI jobs
    ///   - projectStore: ProjectStore for reading/writing projects
    public init(
        jobQueue: JobQueue,
        projectStore: ProjectStore,
        projectDirectoryOverride: URL? = nil
    ) {
        self.jobQueue = jobQueue
        self.projectStore = projectStore
        self.projectDirectoryOverride = projectDirectoryOverride
    }

    /// Configure a cloud AI provider (optional)
    /// - Parameter provider: AI provider implementation
    public func setProvider(_ provider: AIProvider) {
        self.provider = provider
    }

    /// Remove the configured AI provider
    public func clearProvider() {
        self.provider = nil
    }

    /// Check if a cloud provider is configured
    /// - Returns: true if a provider is set
    public func hasProvider() -> Bool {
        provider != nil
    }

    // MARK: - Local Smart Edits (P1)

    /// Suggest edits by detecting silence in audio track
    /// - Parameters:
    ///   - projectId: Project to analyze
    ///   - options: Silence detection options
    /// - Returns: JobId for tracking progress
    public func suggestSilenceEdits(
        projectId: ProjectId,
        options: SilenceDetectionOptions = .default
    ) async throws -> JobId {
        let project = try await projectStore.loadProject(projectId: projectId)

        // Validate audio source
        guard let audioPath = getAudioPath(for: project) else {
            throw AIServiceError.noAudioTrack
        }

        let jobId = await jobQueue.createJob(type: .aiSuggestion, projectId: projectId)

        let task = Task {
            await performSilenceDetection(
                jobId: jobId,
                projectId: projectId,
                audioPath: audioPath,
                options: options
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

    /// Suggest chapters based on transcript content
    /// - Parameters:
    ///   - projectId: Project to analyze
    ///   - options: Chapter suggestion options
    /// - Returns: JobId for tracking progress
    public func suggestChapters(
        projectId: ProjectId,
        options: ChapterSuggestionOptions = .default
    ) async throws -> JobId {
        // Load project to validate it exists
        _ = try await projectStore.loadProject(projectId: projectId)

        // Validate transcript exists
        let transcriptPath = getTranscriptPath(for: projectId)
        guard fileManager.fileExists(atPath: transcriptPath.path) else {
            throw AIServiceError.transcriptNotFound
        }

        let jobId = await jobQueue.createJob(type: .aiSuggestion, projectId: projectId)

        let task = Task {
            await performChapterSuggestion(
                jobId: jobId,
                projectId: projectId,
                transcriptPath: transcriptPath,
                options: options
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

    // MARK: - Cloud Provider Features (P2, Future)

    /// Generate a background asset using a cloud AI provider
    /// - Parameters:
    ///   - projectId: Project to generate background for
    ///   - prompt: Text prompt describing the desired background
    ///   - options: Generation options
    /// - Returns: JobId for tracking progress
    public func generateBackground(
        projectId: ProjectId,
        prompt: String,
        options: BackgroundGenerationOptions = .default
    ) async throws -> JobId {
        guard let provider = provider else {
            throw AIServiceError.noProviderConfigured
        }

        let jobId = await jobQueue.createJob(type: .aiGeneration, projectId: projectId)

        let task = Task {
            await performBackgroundGeneration(
                jobId: jobId,
                projectId: projectId,
                prompt: prompt,
                options: options,
                provider: provider
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

    /// Apply frame-by-frame style transfer (experimental)
    /// - Parameters:
    ///   - projectId: Project to apply style to
    ///   - style: Style description or reference asset
    ///   - options: Style transfer options
    /// - Returns: JobId for tracking progress
    public func applyStyleTransfer(
        projectId: ProjectId,
        style: String,
        options: StyleTransferOptions = .default
    ) async throws -> JobId {
        guard let provider = provider else {
            throw AIServiceError.noProviderConfigured
        }

        let jobId = await jobQueue.createJob(type: .aiGeneration, projectId: projectId)

        let task = Task {
            await performStyleTransfer(
                jobId: jobId,
                projectId: projectId,
                style: style,
                options: options,
                provider: provider
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

    /// Replace background in camera track (experimental)
    /// - Parameters:
    ///   - projectId: Project to process
    ///   - background: Background asset to use
    ///   - options: Background replacement options
    /// - Returns: JobId for tracking progress
    public func replaceCameraBackground(
        projectId: ProjectId,
        background: AssetRef,
        options: BackgroundReplacementOptions = .default
    ) async throws -> JobId {
        guard let provider = provider else {
            throw AIServiceError.noProviderConfigured
        }

        let jobId = await jobQueue.createJob(type: .aiGeneration, projectId: projectId)

        let task = Task {
            await performCameraBackgroundReplacement(
                jobId: jobId,
                projectId: projectId,
                background: background,
                options: options,
                provider: provider
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

}
