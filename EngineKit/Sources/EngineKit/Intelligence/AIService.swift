//
//  AIService.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreMedia

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
    private let jobQueue: JobQueue
    /// Project store for reading/writing projects
    private let projectStore: ProjectStore
    /// File manager for file operations
    private let fileManager = FileManager.default
    /// Optional override for project directory base (useful for tests)
    private let projectDirectoryOverride: URL?

    /// AI provider configuration
    private var provider: AIProvider?

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

    // MARK: - Private Helpers

    /// Perform silence detection
    private func performSilenceDetection(
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
    private func performChapterSuggestion(
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
    private func performBackgroundGeneration(
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
    private func performStyleTransfer(
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
    private func performCameraBackgroundReplacement(
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

    // MARK: - Local AI Implementation

    /// Detect silent regions in audio
    private func detectSilence(
        audioPath: URL,
        threshold: Float,
        minDuration: TimeInterval
    ) async throws -> [SilentRegion] {
        // Load audio asset
        let asset = AVAsset(url: audioPath)
        let duration = try await asset.load(.duration).seconds

        // Use AVAssetReader to analyze audio samples
        let reader = try AVAssetReader(asset: asset)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        guard let audioTrack = audioTrack else {
            throw AIServiceError.audioAnalysisFailed("No audio track found")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var silentRegions: [SilentRegion] = []
        var inSilence = false
        var silenceStart: TimeInterval = 0
        var currentTime: TimeInterval = 0
        let sampleRate: Double = 44100 // Default, will be read from asset

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let samples = sampleBuffer.dataBuffer else {
                try? sampleBuffer.invalidate()
                continue
            }

            // Calculate RMS (root mean square) of audio samples
            let rms = calculateAudioRMS(samples: samples, sampleBuffer: sampleBuffer)

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            currentTime = CMTimeGetSeconds(presentationTime)

            if rms < threshold {
                // Silence detected
                if !inSilence {
                    inSilence = true
                    silenceStart = currentTime
                }
            } else {
                // Sound detected
                if inSilence {
                    let silenceDuration = currentTime - silenceStart
                    if silenceDuration >= minDuration {
                        silentRegions.append(SilentRegion(
                            startTime: silenceStart,
                            endTime: currentTime,
                            duration: silenceDuration
                        ))
                    }
                    inSilence = false
                }
            }

            try? sampleBuffer.invalidate()
        }

        // Handle silence at end of audio
        if inSilence {
            let silenceDuration = duration - silenceStart
            if silenceDuration >= minDuration {
                silentRegions.append(SilentRegion(
                    startTime: silenceStart,
                    endTime: duration,
                    duration: silenceDuration
                ))
            }
        }

        reader.cancelReading()

        return silentRegions
    }

    /// Calculate RMS of audio samples
    private func calculateAudioRMS(samples: CMBlockBuffer, sampleBuffer: CMSampleBuffer) -> Float {
        var rms: Float = 0.0

        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            samples,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let pointer = dataPointer else {
            return rms
        }

        let dataLength = CMBlockBufferGetDataLength(samples)
        let sampleCount = dataLength / MemoryLayout<Int16>.size
        let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }

        var sum: Float = 0
        for i in 0..<sampleCount {
            let sample = Float(abs(Int16(int16Pointer[i])))
            sum += sample * sample
        }

        rms = sqrt(sum / Float(sampleCount))
        return rms / Float(Int16.max)
    }

    /// Suggest chapters from transcript
    private func suggestChaptersFromTranscript(
        transcript: Transcript,
        minChapterDuration: TimeInterval,
        maxChapters: Int
    ) async throws -> [ChapterSuggestion] {
        var chapters: [ChapterSuggestion] = []
        var currentChapterSegments: [Transcript.Segment] = []
        var chapterStartTime: TimeInterval = 0

        for segment in transcript.segments {
            currentChapterSegments.append(segment)

            let chapterDuration = segment.endTime - chapterStartTime

            // Check if we should end the chapter
            if chapterDuration >= minChapterDuration || isChapterBoundary(segment: segment) {
                // Create chapter from segments
                let chapter = createChapterFromSegments(
                    segments: currentChapterSegments,
                    startTime: chapterStartTime,
                    endTime: segment.endTime
                )
                chapters.append(chapter)

                // Start new chapter
                currentChapterSegments = []
                chapterStartTime = segment.endTime

                // Check if we've reached max chapters
                if chapters.count >= maxChapters {
                    break
                }
            }
        }

        // Handle remaining segments
        if !currentChapterSegments.isEmpty {
            let lastSegment = currentChapterSegments.last!
            let chapter = createChapterFromSegments(
                segments: currentChapterSegments,
                startTime: chapterStartTime,
                endTime: lastSegment.endTime
            )
            chapters.append(chapter)
        }

        return chapters
    }

    /// Check if a segment is a chapter boundary
    private func isChapterBoundary(segment: Transcript.Segment) -> Bool {
        // Simple heuristic: pause > 2 seconds or question mark/exclamation
        let gap = segment.startTime - (segment.endTime)
        let text = segment.text.lowercased()

        return gap > 2.0 ||
               text.hasSuffix("?") ||
               text.hasSuffix("!") ||
               text.contains("chapter") ||
               text.contains("section") ||
               text.contains("next")
    }

    /// Create chapter from transcript segments
    private func createChapterFromSegments(
        segments: [Transcript.Segment],
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> ChapterSuggestion {
        // Combine text from all segments
        let text = segments.map { $0.text }.joined(separator: " ")

        // Extract keywords (simple: most frequent words)
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let wordCounts = Dictionary(grouping: words, by: { $0 }).mapValues { $0.count }
        let sortedWords = wordCounts.sorted { $0.value > $1.value }
        let keywords = Array(sortedWords.prefix(5).map { $0.key })

        // Generate title from first few words
        let titleWords = words.prefix(5)
        let title = titleWords.joined(separator: " ").capitalized

        // Generate summary from first and last sentences
        let summary = "\(text.prefix(100))..."

        return ChapterSuggestion(
            title: title,
            startTime: startTime,
            endTime: endTime,
            confidence: 0.7,
            summary: summary,
            keywords: keywords
        )
    }

    // MARK: - File Helpers

    private func getProjectDirectory(for projectId: ProjectId) -> URL {
        if let baseDirectory = projectDirectoryOverride {
            return baseDirectory.appendingPathComponent(projectId.uuidString)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectsDir = appSupport.appendingPathComponent("ProjectStudio/Projects")
        return projectsDir.appendingPathComponent(projectId.uuidString)
    }

    private func getAudioPath(for project: Project) -> String? {
        // Prefer mic audio, fall back to system audio
        if let micPath = project.sources.audio?.mic?.path {
            return micPath
        }
        return project.sources.audio?.system?.path
    }

    private func getTranscriptPath(for projectId: ProjectId) -> URL {
        let projectDir = getProjectDirectory(for: projectId)
        return projectDir.appendingPathComponent("transcript/transcript.json")
    }

    private func saveSuggestions(_ suggestions: [Suggestion], for projectId: ProjectId) async {
        // Save suggestions to project metadata
        let projectDir = getProjectDirectory(for: projectId)
        let suggestionsPath = projectDir.appendingPathComponent("ai_suggestions.json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(suggestions)
            try data.write(to: suggestionsPath)

            await EngineKit.logging.debug(
                category: .ai,
                "Saved \(suggestions.count) suggestions to \(suggestionsPath.path)"
            )
        } catch {
            await EngineKit.logging.error(
                category: .ai,
                "Failed to save suggestions: \(error.localizedDescription)"
            )
        }
    }

    private func saveGeneratedAsset(_ assetRef: AssetRef, for projectId: ProjectId) async throws -> String {
        let projectDir = getProjectDirectory(for: projectId)
        let assetsDir = projectDir.appendingPathComponent("assets")
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Download/copy asset to project directory
        let destinationPath = assetsDir.appendingPathComponent(assetRef.filename)
        try assetRef.data.write(to: destinationPath)

        let relativePath = "assets/\(assetRef.filename)"
        return relativePath
    }
}

// MARK: - Supporting Types

/// Silent region in audio
private struct SilentRegion {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
}

/// Chapter suggestion from transcript
private struct ChapterSuggestion {
    let title: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let summary: String
    let keywords: [String]
}

/// Transcript model for AI analysis
private struct Transcript: Codable {
    let segments: [Segment]

    struct Segment: Codable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }
}
