//
//  AISuggestionsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-K, P2 Task 1: AI Suggestions Panel
//

import Combine
import SwiftUI
import EngineKit

/// AI Suggestions panel for displaying and applying AI-generated editing suggestions
struct AISuggestionsView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval

    @StateObject private var viewModel = AISuggestionsViewModel()
    @State private var showChapterManagement = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("AI Suggestions") {
                if hasChapterSuggestions {
                    Button("Manage Chapters") {
                        showChapterManagement = true
                    }
                    .buttonStyle(.bordered)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Content
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if viewModel.suggestions.isEmpty {
                emptyView
            } else {
                suggestionList
            }
        }
        .modalFrame(.large)
        .onAppear {
            Task {
                await viewModel.loadSuggestions(for: editor.project.projectId)
            }
        }
        .sheet(isPresented: $showChapterManagement) {
            ChapterManagementView(
                editor: editor,
                playheadTime: $playheadTime,
                suggestions: $viewModel.suggestions
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(viewModel.loadingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to load suggestions")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await viewModel.loadSuggestions(for: editor.project.projectId)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No AI Suggestions")
                .font(.headline)

            Text("Generate suggestions to improve your video")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                suggestionButton(
                    title: "Detect Silence",
                    icon: "waveform.path",
                    description: "Find silent sections to remove",
                    action: {
                        Task {
                            await viewModel.generateSilenceSuggestions(for: editor.project.projectId)
                        }
                    }
                )

                suggestionButton(
                    title: "Suggest Chapters",
                    icon: "bookmark",
                    description: "Create chapters from transcript",
                    action: {
                        Task {
                            await viewModel.generateChapterSuggestions(for: editor.project.projectId)
                        }
                    }
                )
                .disabled(!hasTranscript)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        onApply: {
                            Task {
                                await applySuggestion(suggestion)
                            }
                        },
                        onSeek: {
                            playheadTime = suggestion.timelineIn
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteSuggestion(suggestion.id)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }

    private func suggestionButton(
        title: String,
        icon: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var hasTranscript: Bool {
        // Check if transcript exists
        // This is a placeholder - actual implementation would check file system
        true
    }

    private func applySuggestion(_ suggestion: Suggestion) async {
        switch suggestion.type {
        case .removeSilence:
            await applySilenceRemoval(suggestion)
        case .createChapter:
            await applyChapterCreation(suggestion)
        default:
            break
        }

        // Remove suggestion after applying
        await viewModel.deleteSuggestion(suggestion.id)
    }

    private func applySilenceRemoval(_ suggestion: Suggestion) async {
        // Delete the silent region from timeline
        let _ = await editor.deleteRange(
            from: suggestion.timelineIn,
            to: suggestion.timelineOut
        )
    }

    private func applyChapterCreation(_ suggestion: Suggestion) async {
        // Extract metadata from suggestion
        let title = suggestion.metadata("title", as: String.self) ?? "Untitled Chapter"
        let summary = suggestion.metadata("summary", as: String.self)
        let keywords = suggestion.metadata("keywords", as: [String].self) ?? []

        // Create chapter
        let chapter = Project.Chapter(
            title: title,
            startTime: suggestion.timelineIn,
            endTime: suggestion.timelineOut,
            summary: summary,
            keywords: keywords
        )

        // Add to project via ProjectEditor
        _ = await editor.addChapter(chapter)
    }

    // MARK: - Computed Properties

    private var hasChapterSuggestions: Bool {
        !viewModel.suggestions.filter { $0.type == .createChapter }.isEmpty
    }
}

