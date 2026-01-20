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
        let added = await editor.applyChapterSuggestions(from: suggestions)

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

// MARK: - Chapter Row

/// Row view for a single chapter in the project
struct ChapterRow: View {
    let chapter: Project.Chapter
    let isEditing: Bool
    @Binding var editedTitle: String
    @Binding var editedSummary: String
    @Binding var editedKeywords: String
    let onSeek: () -> Void
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Editing mode
                VStack(alignment: .leading, spacing: 8) {
                    // Title editing
                    TextField("Chapter Title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)

                    // Summary editing
                    TextField("Summary (optional)", text: $editedSummary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    // Keywords editing
                    TextField("Keywords (comma-separated)", text: $editedKeywords)
                        .textFieldStyle(.roundedBorder)

                    // Action buttons
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            } else {
                // Display mode
                HStack(alignment: .top, spacing: 12) {
                    // Icon
                    Image(systemName: "bookmark.fill")
                        .font(.title2)
                        .foregroundStyle(Color.blue)
                        .frame(width: 28)

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        // Title
                        Text(chapter.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        // Time range
                        Text(timeRangeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Summary (if exists)
                        if let summary = chapter.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        // Keywords (if exist)
                        if !chapter.keywords.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(chapter.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()

                    // Actions
                    HStack(spacing: 8) {
                        Button(action: onSeek) {
                            Image(systemName: "play.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Seek to chapter start")

                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit chapter")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete chapter")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
    }

    private var timeRangeText: String {
        let start = String(format: "%.1f", chapter.startTime)
        let end = String(format: "%.1f", chapter.endTime)
        let duration = String(format: "%.1f", chapter.duration)
        return "\(start)s - \(end)s (\(duration)s)"
    }
}

// MARK: - Suggested Chapter Row

/// Row view for a suggested chapter from AI
struct SuggestedChapterRow: View {
    let suggestion: Suggestion
    let onSeek: () -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                if let title = suggestion.metadata("title", as: String.self) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Suggested Chapter")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Time range
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Confidence
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                    Text("\(Int(suggestion.confidence * 100))% confidence")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                // Summary (if exists)
                if let summary = suggestion.metadata("summary", as: String.self), !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: onSeek) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview chapter")

                Button(action: onApply) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Apply chapter")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss suggestion")
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var timeRangeText: String {
        let start = String(format: "%.1f", suggestion.timelineIn)
        let end = String(format: "%.1f", suggestion.timelineOut)
        let duration = String(format: "%.1f", suggestion.timelineOut - suggestion.timelineIn)
        return "\(start)s - \(end)s (\(duration)s)"
    }
}

// MARK: - Flow Layout

/// Simple flow layout for keyword tags
struct FlowLayout: Layout {
    var spacing: Double = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CoreFoundation.CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CoreFoundation.CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CoreFoundation.CGSize = .zero
        var positions: [CoreFoundation.CGPoint] = []

        init(in maxWidth: Double, subviews: Subviews, spacing: Double) {
            var currentX: Double = 0
            var currentY: Double = 0
            var lineHeight: Double = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CoreFoundation.CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CoreFoundation.CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
