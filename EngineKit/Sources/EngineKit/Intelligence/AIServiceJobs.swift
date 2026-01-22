//
//  AIServiceJobs.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension AIService {
    /// Perform silence detection
    func performSilenceDetection(
        jobId: JobId,
        projectId: ProjectId,
        audioPath: String,
        options: SilenceDetectionOptions
    ) async {
        do {
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)

            let projectDirectory = getProjectDirectory(for: projectId)
            let audioFullPath = projectDirectory.appendingPathComponent(audioPath)

            // Analyze audio for silence
            let silentRegions = try await detectSilence(
                audioPath: audioFullPath,
                threshold: options.silenceThreshold,
                minDuration: options.minSilenceDuration
            )

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            // Convert silent regions to edit suggestions
            let suggestions = silentRegions.map { region in
                Suggestion(
                    id: UUID(),
                    type: .removeSilence,
                    title: "Remove Silence (\(String(format: "%.1f", region.duration))s)",
                    description: "Remove silent region from \(String(format: "%.1f", region.startTime))s to \(String(format: "%.1f", region.endTime))s",
                    confidence: 0.9,
                    timelineIn: region.startTime,
                    timelineOut: region.endTime,
                    metadata: [
                        "silenceDuration": AIAnyCodable(region.duration),
                        "threshold": AIAnyCodable(options.silenceThreshold)
                    ]
                )
            }

            // Save suggestions to project
            await saveSuggestions(suggestions, for: projectId)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 1.0)
            await jobQueue.completeJob(jobId: jobId)

            await EngineKit.logging.info(
                category: .ai,
                "Silence detection complete: found \(silentRegions.count) silent regions"
            )
        } catch {
            let jobError = Job.JobError(
                code: "SILENCE_DETECTION_FAILED",
                message: error.localizedDescription,
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await EngineKit.logging.error(
                category: .ai,
                "Silence detection failed: \(error.localizedDescription)"
            )
        }
    }

    /// Perform chapter suggestion
    func performChapterSuggestion(
        jobId: JobId,
        projectId: ProjectId,
        transcriptPath: URL,
        options: ChapterSuggestionOptions
    ) async {
        do {
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)

            // Load transcript
            let transcriptData = try Data(contentsOf: transcriptPath)
            let transcript = try JSONDecoder().decode(Transcript.self, from: transcriptData)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.3)

            // Analyze transcript for chapter boundaries
            let chapters = try await suggestChaptersFromTranscript(
                transcript: transcript,
                minChapterDuration: options.minChapterDuration,
                maxChapters: options.maxChapters
            )

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            // Convert chapters to suggestions
            let suggestions = chapters.map { chapter in
                Suggestion(
                    id: UUID(),
                    type: .createChapter,
                    title: chapter.title,
                    description: "Chapter from \(String(format: "%.1f", chapter.startTime))s to \(String(format: "%.1f", chapter.endTime))s",
                    confidence: chapter.confidence,
                    timelineIn: chapter.startTime,
                    timelineOut: chapter.endTime,
                    metadata: [
                        "summary": AIAnyCodable(chapter.summary),
                        "keywords": AIAnyCodable(chapter.keywords)
                    ]
                )
            }

            // Save suggestions to project
            await saveSuggestions(suggestions, for: projectId)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 1.0)
            await jobQueue.completeJob(jobId: jobId)

            await EngineKit.logging.info(
                category: .ai,
                "Chapter suggestion complete: suggested \(chapters.count) chapters"
            )
        } catch {
            let jobError = Job.JobError(
                code: "CHAPTER_SUGGESTION_FAILED",
                message: error.localizedDescription,
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await EngineKit.logging.error(
                category: .ai,
                "Chapter suggestion failed: \(error.localizedDescription)"
            )
        }
    }

    /// Perform background generation
    func performBackgroundGeneration(
        jobId: JobId,
        projectId: ProjectId,
        prompt: String,
        options: BackgroundGenerationOptions,
        provider: AIProvider
    ) async {
        do {
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)

            // Call provider to generate background
            let assetRef = try await provider.generateBackground(
                prompt: prompt,
                width: options.width,
                height: options.height,
                style: options.style
            )

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            // Save generated asset to project
            let savedPath = try await saveGeneratedAsset(assetRef, for: projectId)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 1.0)
            await jobQueue.completeJob(jobId: jobId)

            await EngineKit.logging.info(
                category: .ai,
                "Background generation complete: \(savedPath)"
            )
        } catch {
            let jobError = Job.JobError(
                code: "GENERATION_FAILED",
                message: error.localizedDescription,
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await EngineKit.logging.error(
                category: .ai,
                "Background generation failed: \(error.localizedDescription)"
            )
        }
    }

    /// Perform style transfer
    func performStyleTransfer(
        jobId: JobId,
        projectId: ProjectId,
        style: String,
        options: StyleTransferOptions,
        provider: AIProvider
    ) async {
        do {
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)

            // Call provider to apply style transfer
            let assetRef = try await provider.applyStyleTransfer(
                projectId: projectId,
                style: style,
                strength: options.strength
            )

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            // Save processed video
            let savedPath = try await saveGeneratedAsset(assetRef, for: projectId)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 1.0)
            await jobQueue.completeJob(jobId: jobId)

            await EngineKit.logging.info(
                category: .ai,
                "Style transfer complete: \(savedPath)"
            )
        } catch {
            let jobError = Job.JobError(
                code: "GENERATION_FAILED",
                message: error.localizedDescription,
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await EngineKit.logging.error(
                category: .ai,
                "Style transfer failed: \(error.localizedDescription)"
            )
        }
    }

    /// Perform camera background replacement
    func performCameraBackgroundReplacement(
        jobId: JobId,
        projectId: ProjectId,
        background: AssetRef,
        options: BackgroundReplacementOptions,
        provider: AIProvider
    ) async {
        do {
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)

            // Call provider to replace background
            let assetRef = try await provider.replaceCameraBackground(
                projectId: projectId,
                background: background,
                edgeSmoothness: options.edgeSmoothness
            )

            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            // Save processed video
            let savedPath = try await saveGeneratedAsset(assetRef, for: projectId)

            await jobQueue.updateJobProgress(jobId: jobId, progress: 1.0)
            await jobQueue.completeJob(jobId: jobId)

            await EngineKit.logging.info(
                category: .ai,
                "Camera background replacement complete: \(savedPath)"
            )
        } catch {
            let jobError = Job.JobError(
                code: "GENERATION_FAILED",
                message: error.localizedDescription,
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
            await EngineKit.logging.error(
                category: .ai,
                "Camera background replacement failed: \(error.localizedDescription)"
            )
        }
    }
}
