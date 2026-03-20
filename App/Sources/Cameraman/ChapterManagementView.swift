//
//  ChapterManagementView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-K, P2 Task 2: Automatic Chapters
//

import SwiftUI
import EngineKit

/// Chapter management interface for displaying, editing, and applying chapter markers
struct ChapterManagementView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval
    @Binding var suggestions: [Suggestion]

    @State private var editingChapterId: UUID?
    @State private var editedTitle: String = ""
    @State private var editedSummary: String = ""
    @State private var editedKeywords: String = ""
    @State private var showApplyConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chapter Management")
                    .font(.headline)

                Spacer()

                if hasChapterSuggestions {
                    Button("Apply All") {
                        showApplyConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            if editor.project.chapters.isEmpty && !hasChapterSuggestions {
                emptyView
            } else {
                chapterList
            }
        }
        .frame(width: 700, height: 600)
        .alert("Apply Chapters", isPresented: $showApplyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply") {
                Task {
                    await applyAllChapterSuggestions()
                }
            }
        } message: {
            Text("Apply \(chapterSuggestionsCount) suggested chapter markers to the project?")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Chapters")
                .font(.headline)

            Text("Generate chapter suggestions from your transcript to organize your video")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if !hasTranscript {
                Text("Note: Transcription must be completed before generating chapters")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Section: Suggested Chapters (if any)
                if hasChapterSuggestions {
                    Section {
                        ForEach(chapterSuggestions) { suggestion in
                            SuggestedChapterRow(
                                suggestion: suggestion,
                                onSeek: { playheadTime = suggestion.timelineIn },
                                onApply: {
                                    Task {
                                        await applyChapterSuggestion(suggestion)
                                    }
                                },
                                onDismiss: {
                                    Task {
                                        await dismissSuggestion(suggestion)
                                    }
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text("Suggested Chapters")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("(\(chapterSuggestionsCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }

                // Section: Applied Chapters
                if !editor.project.chapters.isEmpty {
                    Section {
                        ForEach(editor.project.chapters) { chapter in
                            ChapterRow(
                                chapter: chapter,
                                isEditing: editingChapterId == chapter.id,
                                editedTitle: $editedTitle,
                                editedSummary: $editedSummary,
                                editedKeywords: $editedKeywords,
                                onSeek: { playheadTime = chapter.startTime },
                                onEdit: { startEditing(chapter) },
                                onSave: { Task { await saveChapter(chapter) } },
                                onCancel: { cancelEditing() },
                                onDelete: { Task { await deleteChapter(chapter) } }
                            )
                        }
                    } header: {
                        HStack {
                            Text("Project Chapters")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("(\(editor.project.chapters.count))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, hasChapterSuggestions ? 16 : 0)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var hasChapterSuggestions: Bool {
        !chapterSuggestions.isEmpty
    }

    private var chapterSuggestions: [Suggestion] {
        suggestions.filter { $0.type == .createChapter }
    }

    private var chapterSuggestionsCount: Int {
        chapterSuggestions.count
    }

    private var hasTranscript: Bool {
        // Check if project has captions/transcript
        editor.project.captions != nil
    }

    // MARK: - Actions

    private func startEditing(_ chapter: Project.Chapter) {
        editingChapterId = chapter.id
        editedTitle = chapter.title
        editedSummary = chapter.summary ?? ""
        editedKeywords = chapter.keywords.joined(separator: ", ")
    }

    private func cancelEditing() {
        editingChapterId = nil
        editedTitle = ""
        editedSummary = ""
        editedKeywords = ""
    }

    private func saveChapter(_ chapter: Project.Chapter) async {
        let keywordsArray = editedKeywords.isEmpty ? [] : editedKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        _ = await editor.updateChapter(
            chapterId: chapter.id,
            title: editedTitle.isEmpty ? chapter.title : editedTitle,
            summary: editedSummary.isEmpty ? nil : editedSummary,
            keywords: keywordsArray
        )

        editingChapterId = nil
        editedTitle = ""
        editedSummary = ""
        editedKeywords = ""
    }

    private func deleteChapter(_ chapter: Project.Chapter) async {
        _ = await editor.deleteChapter(chapterId: chapter.id)
    }

    private func applyChapterSuggestion(_ suggestion: Suggestion) async {
        // Extract metadata
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

        // Add to project
        _ = await editor.addChapter(chapter)

        // Remove from suggestions
        await dismissSuggestion(suggestion)
    }

    private func applyAllChapterSuggestions() async {
        _ = await editor.applyChapterSuggestions(from: suggestions)

        // Remove applied suggestions
        suggestions.removeAll { $0.type == .createChapter }

        // Refresh project
        await editor.refreshProject()
    }

    private func dismissSuggestion(_ suggestion: Suggestion) async {
        // Remove from local suggestions array
        suggestions.removeAll { $0.id == suggestion.id }
    }
}

