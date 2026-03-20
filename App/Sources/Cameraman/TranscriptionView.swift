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

