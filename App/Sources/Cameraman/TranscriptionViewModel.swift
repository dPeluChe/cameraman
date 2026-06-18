//
//  TranscriptionViewModel.swift
//  App
//
//  Extracted from TranscriptionView.swift
//  View model for transcription operations
//

import AppKit
import Combine
import SwiftUI
import EngineKit
import UniformTypeIdentifiers

/// View model for transcription operations
@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var transcriptionState: TranscriptionState = .notStarted
    @Published var transcriptionProgress: Double = 0
    @Published var progressMessage: String = ""
    @Published var transcript: TranscriptionEngine.Transcript?
    @Published var errorMessage: String?
    @Published var isStarting = false
    @Published var selectedSegmentId: Int?
    @Published var editingSegmentId: Int?
    @Published var editedTexts: [Int: String] = [:]
    @Published var burnInCaptions: Bool = false
    @Published var showingExportOptions: Bool = false

    @Published var selectedLanguage: String?
    private var transcriptionJobId: JobId?

    enum TranscriptionState {
        case notStarted
        case inProgress
        case completed
        case failed
    }

    enum ExportFormat: String {
        case srt
        case vtt
        case txt
    }

    func checkTranscriptionStatus(project: Project) {
        // A transcript may already exist on disk from a previous run — load it so
        // the user can review/edit (and re-add to the timeline) without re-running.
        guard project.captions != nil else { return }
        Task { await loadExistingTranscript(projectId: project.projectId) }
    }

    private func loadExistingTranscript(projectId: ProjectId) async {
        do {
            let dir = try await ProjectLibrary.shared.getProjectDirectory(projectId: projectId)
            let url = dir.appendingPathComponent("transcript/transcript.json")
            let data = try Data(contentsOf: url)
            transcript = try JSONDecoder().decode(TranscriptionEngine.Transcript.self, from: data)
            transcriptionState = .completed
        } catch {
            LogDebug(.transcription, "No existing transcript to load: \(error.localizedDescription)")
        }
    }

    /// Run a real transcription job via the EngineKit pipeline: extract audio,
    /// run the (offline) recognizer, write transcript.json + SRT/VTT, then load
    /// the produced transcript back for review/editing.
    func startTranscription(project: Project, language: String?) async {
        isStarting = true
        defer { isStarting = false }

        transcriptionState = .inProgress
        transcriptionProgress = 0
        errorMessage = nil
        progressMessage = "Preparing…"

        do {
            // Persist latest edits so the engine loads the project with its sources.
            try? await ProjectLibrary.shared.updateProject(project)

            let engine = try await ProjectLibrary.shared.getTranscriptionEngine()
            let jobQueue = try await ProjectLibrary.shared.getJobQueue()

            let options = TranscriptionEngine.Options(language: language)
            let jobId = try await engine.transcribe(projectId: project.projectId, options: options)
            transcriptionJobId = jobId

            try await pollJob(jobId: jobId, jobQueue: jobQueue)

            let dir = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
            let transcriptURL = dir.appendingPathComponent("transcript/transcript.json")
            let data = try Data(contentsOf: transcriptURL)
            transcript = try JSONDecoder().decode(TranscriptionEngine.Transcript.self, from: data)

            transcriptionProgress = 1
            transcriptionState = .completed
        } catch is CancellationError {
            transcriptionState = .notStarted
            transcriptionProgress = 0
        } catch {
            errorMessage = error.localizedDescription
            transcriptionState = .failed
        }
    }

    /// Poll the job queue until the transcription job reaches a terminal state,
    /// surfacing progress along the way.
    private func pollJob(jobId: JobId, jobQueue: JobQueue) async throws {
        while true {
            if Task.isCancelled { throw CancellationError() }

            if let job = await jobQueue.getJob(jobId: jobId) {
                switch job.status {
                case .running(let progress):
                    transcriptionProgress = progress
                    progressMessage = progressLabel(for: progress)
                case .success:
                    return
                case .failed:
                    throw TranscriptionError.transcriptionFailed(
                        job.error?.message ?? "Transcription failed"
                    )
                case .canceled:
                    throw CancellationError()
                case .queued:
                    progressMessage = "Queued…"
                }
            }

            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func progressLabel(for progress: Double) -> String {
        switch progress {
        case ..<0.3: return "Extracting audio…"
        case ..<0.8: return "Transcribing audio…"
        case ..<0.9: return "Generating captions…"
        default: return "Finalizing…"
        }
    }

    func cancelTranscription() async {
        if let jobId = transcriptionJobId,
           let queue = try? await ProjectLibrary.shared.getJobQueue() {
            try? await queue.cancelJob(jobId: jobId)
        }
        transcriptionJobId = nil
        transcriptionState = .notStarted
        transcriptionProgress = 0
    }

    func updateSegmentText(segmentId: Int, text: String) {
        editedTexts[segmentId] = text
    }

    func editedText(for segment: TranscriptionEngine.Transcript.Segment) -> String {
        editedTexts[segment.id] ?? segment.text
    }

    func startEditing(segment: TranscriptionEngine.Transcript.Segment) {
        editingSegmentId = segment.id
        selectedSegmentId = segment.id
        if editedTexts[segment.id] == nil {
            editedTexts[segment.id] = segment.text
        }
    }

    func finishEditing() {
        editingSegmentId = nil
    }

    func cancelEditing() {
        if let editingId = editingSegmentId {
            editedTexts.removeValue(forKey: editingId)
        }
        editingSegmentId = nil
    }

    func exportCaptions(format: ExportFormat) async {
        guard let transcript = transcript else { return }

        let content: String
        switch format {
        case .txt:
            content = transcript.segments
                .map { editedText(for: $0) }
                .joined(separator: "\n")
        case .srt:
            content = transcript.segments.enumerated().map { index, seg in
                let start = Self.srtTimestamp(seg.start)
                let end = Self.srtTimestamp(seg.end)
                return "\(index + 1)\n\(start) --> \(end)\n\(editedText(for: seg))"
            }.joined(separator: "\n\n")
        case .vtt:
            let body = transcript.segments.map { seg in
                let start = Self.vttTimestamp(seg.start)
                let end = Self.vttTimestamp(seg.end)
                return "\(start) --> \(end)\n\(editedText(for: seg))"
            }.joined(separator: "\n\n")
            content = "WEBVTT\n\n\(body)"
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "transcript.\(format.rawValue)"
        panel.allowedContentTypes = [.plainText]
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func srtTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private static func vttTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

// MARK: - Transcript Segment Row

/// Single transcript segment row
struct TranscriptSegmentRow: View {
    let segment: TranscriptionEngine.Transcript.Segment
    let index: Int
    let isSelected: Bool
    let isEditing: Bool
    let editedText: String
    let onTextChange: (String) -> Void
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index number
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 4)

            // Timestamp and text
            VStack(alignment: .leading, spacing: 4) {
                // Timestamp
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(formatTimestamp(segment.start))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)

                // Text content
                if isEditing {
                    TextEditor(text: Binding(
                        get: { editedText },
                        set: onTextChange
                    ))
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                } else {
                    Text(editedText)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            // Edit/Save button
            if isEditing {
                HStack(spacing: 4) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit text")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onTap()
            }
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
}
