//
//  TranscriptionEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// TranscriptionEngine handles offline speech-to-text transcription using Whisper.cpp
public actor TranscriptionEngine {
    /// Shared job queue for async operations
    private let jobQueue: JobQueue
    /// Project store for reading/writing projects
    private let projectStore: ProjectStore
    /// File manager for file operations
    private let fileManager = FileManager.default

    /// Initialize TranscriptionEngine
    /// - Parameters:
    ///   - jobQueue: JobQueue for managing transcription jobs
    ///   - projectStore: ProjectStore for reading/writing projects
    public init(jobQueue: JobQueue, projectStore: ProjectStore) {
        self.jobQueue = jobQueue
        self.projectStore = projectStore
    }

    /// Start a transcription job for a project
    /// - Parameters:
    ///   - projectId: Project to transcribe
    ///   - options: Transcription options (model, language, etc.)
    /// - Returns: JobId for tracking progress
    public func transcribe(projectId: ProjectId, options: Options = .default) async throws -> JobId {
        // Load project
        let project = try await projectStore.loadProject(projectId: projectId)

        // Validate audio source
        guard let audioPath = getAudioPath(for: project) else {
            throw TranscriptionError.noAudioSource
        }

        // Create job
        let jobId = await jobQueue.createJob(type: .transcribe, projectId: projectId)

        // Start transcription task
        let task = Task {
            await performTranscription(
                jobId: jobId,
                projectId: projectId,
                audioPath: audioPath,
                options: options
            )
        }

        await jobQueue.startJob(jobId: jobId, task: task)

        return jobId
    }

    /// Perform the actual transcription work
    private func performTranscription(
        jobId: JobId,
        projectId: ProjectId,
        audioPath: String,
        options: Options
    ) async {
        do {
            // Resolve the project directory from the store so transcript.json lands
            // where the rest of the app reads it (honors a custom store base dir).
            let projectDirectory = try await projectStore.projectDirectoryURL(for: projectId)
            let audioFullPath = projectDirectory.appendingPathComponent(audioPath)

            // Create transcript directory
            let transcriptDirectory = projectDirectory.appendingPathComponent("transcript")
            try fileManager.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)

            // Step 1: Extract audio to WAV format (16kHz, mono)
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.1)
            let wavPath = transcriptDirectory.appendingPathComponent("audio.wav")

            try await extractAudioToWAV(
                source: audioFullPath,
                output: wavPath,
                sampleRate: options.sampleRate
            )

            // Step 2: Run transcription. 0.3 = loading model (first run downloads
            // it — the long, opaque phase); bumped to 0.55 once it's ready.
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.3)
            let transcriptPath = transcriptDirectory.appendingPathComponent("transcript.json")

            try await runWhisperTranscription(
                jobId: jobId,
                audioPath: wavPath,
                outputPath: transcriptPath,
                options: options
            )

            // Step 3: Generate SRT and VTT files
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.8)

            let transcriptData = try Data(contentsOf: transcriptPath)
            let transcript = try JSONDecoder().decode(Transcript.self, from: transcriptData)

            let srtPath = transcriptDirectory.appendingPathComponent("captions.srt")
            let vttPath = transcriptDirectory.appendingPathComponent("captions.vtt")

            try generateSRT(transcript: transcript, outputPath: srtPath)
            try generateVTT(transcript: transcript, outputPath: vttPath)

            // Step 4: Update project with captions
            await jobQueue.updateJobProgress(jobId: jobId, progress: 0.9)

            let relativeSrtPath = "transcript/captions.srt"
            let relativeVttPath = "transcript/captions.vtt"

            var updatedProject = try await projectStore.loadProject(projectId: projectId)
            updatedProject.captions = Project.Captions(
                language: options.language ?? "auto",
                srtPath: relativeSrtPath,
                vttPath: relativeVttPath
            )

            try await projectStore.saveProject(updatedProject)

            // Complete job
            await jobQueue.completeJob(jobId: jobId)

        } catch {
            // Fail job with error
            let jobError = Job.JobError(
                code: "TRANSCRIPTION_FAILED",
                message: error.localizedDescription,
                details: ["original_error": .string(String(describing: error))],
                recoverable: false
            )
            await jobQueue.failJob(jobId: jobId, error: jobError)
        }
    }

    /// Get the audio path for transcription (prefer mic, fallback to system audio)
    private func getAudioPath(for project: Project) -> String? {
        // Prefer microphone audio if available
        if let micPath = project.primarySources?.audio?.mic?.path {
            return micPath
        }
        // Fallback to system audio
        if let systemPath = project.primarySources?.audio?.system?.path {
            return systemPath
        }
        return nil
    }

    /// Extract audio from source file to WAV format
    private func extractAudioToWAV(
        source: URL,
        output: URL,
        sampleRate: Int
    ) async throws {
        let asset = AVAsset(url: source)

        guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.audioExtractionFailed("No audio track found in source file")
        }

        // Create reader
        let outputURL = output
        try? fileManager.removeItem(at: outputURL) // Remove existing file if any

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw TranscriptionError.audioExtractionFailed("Failed to create asset reader")
        }

        // Configure output for 16-bit PCM mono
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]

        let output = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        // Create writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
            AVLinearPCMIsNonInterleaved: false
        ])

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Copy audio data
        while let sampleBuffer = output.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            writerInput.append(sampleBuffer)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw TranscriptionError.audioExtractionFailed("Asset writer failed: \(writer.error?.localizedDescription ?? "Unknown error")")
        }
    }

    /// Run on-device transcription via WhisperKit (CoreML / Apple Neural Engine)
    /// and write the result as transcript.json. Only runs on Apple Silicon.
    private func runWhisperTranscription(
        jobId: JobId,
        audioPath: URL,
        outputPath: URL,
        options: Options
    ) async throws {
        guard WhisperKitTranscriber.isSupported else {
            throw TranscriptionError.unsupportedHardware
        }

        let result = try await WhisperKitTranscriber.transcribe(
            audioPath: audioPath,
            modelName: options.model.whisperKitName,
            language: options.language,
            translate: options.translate,
            onModelReady: { [jobQueue] in
                await jobQueue.updateJobProgress(jobId: jobId, progress: 0.55)
            }
        )

        let segments = result.segments.enumerated().map { index, segment in
            Transcript.Segment(
                id: index,
                start: segment.start,
                end: segment.end,
                text: segment.text
            )
        }

        let transcript = Transcript(
            language: result.language,
            duration: segments.last?.end ?? 0,
            segments: segments
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(transcript)
        try data.write(to: outputPath)
    }

    /// Generate SRT file from transcript
    private func generateSRT(transcript: Transcript, outputPath: URL) throws {
        var srtContent = ""

        for (index, segment) in transcript.segments.enumerated() {
            let startTime = formatSRTimeString(seconds: segment.start)
            let endTime = formatSRTimeString(seconds: segment.end)

            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "\(segment.text)\n\n"
        }

        try srtContent.write(to: outputPath, atomically: true, encoding: .utf8)
    }

    /// Generate VTT file from transcript
    private func generateVTT(transcript: Transcript, outputPath: URL) throws {
        var vttContent = "WEBVTT\n\n"

        for (index, segment) in transcript.segments.enumerated() {
            let startTime = formatVTTTimeString(seconds: segment.start)
            let endTime = formatVTTTimeString(seconds: segment.end)

            vttContent += "\(index + 1)\n"
            vttContent += "\(startTime) --> \(endTime)\n"
            vttContent += "\(segment.text)\n\n"
        }

        try vttContent.write(to: outputPath, atomically: true, encoding: .utf8)
    }

    /// Format time for SRT (HH:MM:SS,mmm)
    private func formatSRTimeString(seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }

    /// Format time for VTT (HH:MM:SS.mmm)
    private func formatVTTTimeString(seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, milliseconds)
    }
}

// MARK: - Supporting Types

/// Transcription options
public extension TranscriptionEngine {
    struct Options: Equatable {
        /// Whisper model to use
        public let model: Model
        /// Language code (nil = auto-detect)
        public let language: String?
        /// Translate to English instead of transcribing in the source language.
        public let translate: Bool
        /// Sample rate for audio extraction
        public let sampleRate: Int

        public enum Model: String, Equatable {
            case base
            case small
            case medium
            case large

            /// WhisperKit model identifier for this size.
            var whisperKitName: String {
                switch self {
                case .base: return "base"
                case .small: return "small"
                case .medium: return "medium"
                case .large: return "large-v3"
                }
            }
        }

        public init(model: Model = .base, language: String? = nil, translate: Bool = false, sampleRate: Int = 16000) {
            self.model = model
            self.language = language
            self.translate = translate
            self.sampleRate = sampleRate
        }

        public static let `default` = Options()
    }
}

/// Transcript model
public extension TranscriptionEngine {
    struct Transcript: Codable, Equatable {
        public let language: String
        public let duration: TimeInterval
        public let segments: [Segment]

        public struct Segment: Codable, Equatable, Identifiable {
            public let id: Int
            public let start: TimeInterval
            public let end: TimeInterval
            public let text: String
        }
    }
}

/// Availability of on-device transcription.
public extension TranscriptionEngine {
    /// Whether on-device transcription (WhisperKit, CoreML / Apple Neural Engine)
    /// can run on this machine. `false` on Intel Macs.
    static var isAvailable: Bool { WhisperKitTranscriber.isSupported }
}

/// Transcription errors
public enum TranscriptionError: LocalizedError {
    case noAudioSource
    case audioExtractionFailed(String)
    case transcriptionFailed(String)
    case fileNotFound(URL)
    case unsupportedHardware
    case transcriberUnavailable

    public var errorDescription: String? {
        switch self {
        case .noAudioSource:
            return "No audio source found in project. Please record with microphone or system audio enabled."
        case .audioExtractionFailed(let message):
            return "Failed to extract audio: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .unsupportedHardware:
            return "On-device transcription requires a Mac with Apple Silicon. It isn't available on this Mac yet."
        case .transcriberUnavailable:
            return "The transcription engine (WhisperKit) isn't available in this build."
        }
    }
}
