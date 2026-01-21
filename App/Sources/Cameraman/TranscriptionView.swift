//
//  TranscriptionView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import Combine
import SwiftUI
import EngineKit

/// Transcription view for generating and editing video transcriptions
struct TranscriptionView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval

    @StateObject private var viewModel: TranscriptionViewModel
    @Environment(\.dismiss) private var dismiss

    init(editor: ProjectEditor, playheadTime: Binding<TimeInterval>) {
        self.editor = editor
        self._playheadTime = playheadTime
        _viewModel = StateObject(wrappedValue: TranscriptionViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with transcription status
            header

            Divider()

            // Transcription controls or transcript display
            if viewModel.transcriptionState == .notStarted {
                transcriptionPrompt
            } else if viewModel.transcriptionState == .inProgress {
                progressView
            } else if viewModel.transcriptionState == .completed {
                transcriptView
            } else if viewModel.transcriptionState == .failed {
                errorView
            }
        }
        .padding(20)
        .frame(width: 560, height: 400)
        .onAppear {
            viewModel.checkTranscriptionStatus(project: editor.project)
        }
    }

    private var header: some View {
        HStack {
            Text("Transcription")
                .font(.headline)

            Spacer()

            if viewModel.transcriptionState == .completed {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var transcriptionPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Transcript")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Transcribe the audio track of your video to create captions and searchable text.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Language", selection: $viewModel.selectedLanguage) {
                    Text("Auto-detect").tag(nil as String?)
                    Text("English").tag("en" as String?)
                    Text("Spanish").tag("es" as String?)
                    Text("French").tag("fr" as String?)
                    Text("German").tag("de" as String?)
                    Text("Italian").tag("it" as String?)
                    Text("Portuguese").tag("pt" as String?)
                    Text("Chinese").tag("zh" as String?)
                    Text("Japanese").tag("ja" as String?)
                    Text("Korean").tag("ko" as String?)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.startTranscription(
                            projectId: editor.project.projectId,
                            language: viewModel.selectedLanguage
                        )
                    }
                } label: {
                    Label("Generate Transcript", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isStarting)

                if viewModel.isStarting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var progressView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ProgressView(value: viewModel.transcriptionProgress)

                HStack {
                    Text(viewModel.progressMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.transcriptionProgress * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription in progress...")
                    .foregroundStyle(.secondary)

                Text("This may take a few moments depending on the video length.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                Task {
                    await viewModel.cancelTranscription()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var transcriptView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    viewModel.showingExportOptions = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.transcript == nil)

                Menu {
                    Button("SRT Format") {
                        Task {
                            await viewModel.exportCaptions(format: .srt)
                        }
                    }
                    Button("VTT Format") {
                        Task {
                            await viewModel.exportCaptions(format: .vtt)
                        }
                    }
                } label: {
                    Label("Quick Export", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.transcript == nil)

                Spacer()

                Toggle("Burn-in Captions", isOn: $viewModel.burnInCaptions)
                    .toggleStyle(.switch)
                    .help("Embed captions in the exported video")
            }
            .padding(.bottom, 12)

            // Transcript list
            if let transcript = viewModel.transcript {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                index: index,
                                isSelected: viewModel.selectedSegmentId == segment.id,
                                isEditing: viewModel.editingSegmentId == segment.id,
                                editedText: viewModel.editedText(for: segment),
                                onTextChange: { newText in
                                    viewModel.updateSegmentText(segmentId: segment.id, text: newText)
                                },
                                onTap: {
                                    playheadTime = segment.start
                                    viewModel.selectedSegmentId = segment.id
                                },
                                onEdit: {
                                    viewModel.startEditing(segment: segment)
                                },
                                onSave: {
                                    viewModel.finishEditing()
                                },
                                onCancel: {
                                    viewModel.cancelEditing()
                                }
                            )

                            if index < transcript.segments.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("No transcript available")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("The transcript file could not be loaded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Export Captions", isPresented: $viewModel.showingExportOptions, titleVisibility: .visible) {
            Button("SRT Format") {
                Task {
                    await viewModel.exportCaptions(format: .srt)
                }
            }
            Button("VTT Format") {
                Task {
                    await viewModel.exportCaptions(format: .vtt)
                }
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Transcription Failed")
                .font(.headline)

            Text(viewModel.errorMessage ?? "An unknown error occurred")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Retry") {
                    Task {
                        await viewModel.startTranscription(
                            projectId: editor.project.projectId,
                            language: viewModel.selectedLanguage
                        )
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

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
    private var progressTimer: Timer?
    private var projectLibrary: ProjectLibrary?

    enum TranscriptionState {
        case notStarted
        case inProgress
        case completed
        case failed
    }

    enum ExportFormat {
        case srt
        case vtt
    }

    init() {
        self.projectLibrary = ProjectLibrary()
    }

    func checkTranscriptionStatus(project: Project) {
        // Check if project has existing captions
        if project.captions != nil {
            // In production, load existing transcript
            print("Project has existing captions")
        }
    }

    func startTranscription(projectId: ProjectId, language: String?) async {
        isStarting = true
        defer { isStarting = false }

        do {
            guard projectLibrary != nil else {
                throw TranscriptionError.transcriptionFailed("Project library not available")
            }

            transcriptionState = .inProgress
            progressMessage = "Initializing transcription..."

            // Placeholder: Simulate transcription for UI testing
            // In production, this would call TranscriptionEngine via ProjectLibrary
            await simulateTranscription()

        } catch {
            transcriptionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func simulateTranscription() async {
        // Simulate the transcription process for UI testing
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            transcriptionProgress = progress

            if progress < 0.3 {
                progressMessage = "Extracting audio..."
            } else if progress < 0.8 {
                progressMessage = "Transcribing audio..."
            } else if progress < 0.9 {
                progressMessage = "Generating captions..."
            } else {
                progressMessage = "Finalizing..."
            }
        }

        // Create mock transcript for testing using JSON encoding
        let mockTranscriptJSON = """
        {
            "language": "\(selectedLanguage ?? "en")",
            "duration": 60.0,
            "segments": [
                {
                    "id": 0,
                    "start": 0.0,
                    "end": 3.2,
                    "text": "Welcome to this video tutorial"
                },
                {
                    "id": 1,
                    "start": 3.2,
                    "end": 7.5,
                    "text": "In this video, we'll explore how to build a modern macOS application"
                },
                {
                    "id": 2,
                    "start": 7.5,
                    "end": 12.0,
                    "text": "using SwiftUI and the AVFoundation framework"
                },
                {
                    "id": 3,
                    "start": 12.0,
                    "end": 16.8,
                    "text": "We'll cover recording, editing, and exporting videos"
                }
            ]
        }
        """

        do {
            let data = mockTranscriptJSON.data(using: .utf8)!
            transcript = try JSONDecoder().decode(TranscriptionEngine.Transcript.self, from: data)
        } catch {
            print("Failed to decode mock transcript: \(error)")
        }

        transcriptionState = .completed
    }

    func cancelTranscription() async {
        // Cancel transcription by resetting state
        progressTimer?.invalidate()
        progressTimer = nil
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
        // Initialize edited text if not already present
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
        // Placeholder: In production, this would generate SRT/VTT from edited transcripts
        // and save them to the project directory
        print("Exporting captions in \(format) format (placeholder)")
    }
}
