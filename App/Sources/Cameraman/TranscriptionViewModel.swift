//
//  TranscriptionViewModel.swift
//  App
//
//  Extracted from TranscriptionView.swift
//  View model for transcription operations
//

import Combine
import SwiftUI
import EngineKit

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
        self.projectLibrary = ProjectLibrary.shared
    }

    func checkTranscriptionStatus(project: Project) {
        if project.captions != nil {
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

            await simulateTranscription()

        } catch {
            transcriptionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func simulateTranscription() async {
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            try? await Task.sleep(nanoseconds: 200_000_000)

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
        print("Exporting captions in \(format) format (placeholder)")
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
