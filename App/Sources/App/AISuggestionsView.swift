//
//  AISuggestionsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-K, P2 Task 1: AI Suggestions Panel
//

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
            // Header
            HStack {
                Text("AI Suggestions")
                    .font(.headline)

                Spacer()

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
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

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
        .frame(width: 600, height: 500)
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

/// View model for AI Suggestions
@MainActor
final class AISuggestionsViewModel: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published private(set) var errorMessage: String?

    private let projectLibrary = ProjectLibrary()

    func loadSuggestions(for projectId: ProjectId) async {
        isLoading = true
        loadingMessage = "Loading suggestions..."
        errorMessage = nil

        do {
            let projectDirectory = try await projectLibrary.getProjectDirectory(projectId: projectId)
            let suggestionsPath = projectDirectory.appendingPathComponent("ai_suggestions.json")

            // Check if suggestions file exists
            guard FileManager.default.fileExists(atPath: suggestionsPath.path) else {
                suggestions = []
                isLoading = false
                return
            }

            // Load suggestions
            let data = try Data(contentsOf: suggestionsPath)
            suggestions = try JSONDecoder().decode([Suggestion].self, from: data)

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func generateSilenceSuggestions(for projectId: ProjectId) async {
        isLoading = true
        loadingMessage = "Analyzing audio for silence..."
        errorMessage = nil

        do {
            let library = ProjectLibrary()
            let aiService = try await library.getAIService()

            // Use default silence detection options
            let options = SilenceDetectionOptions.default

            let jobId = try await aiService.suggestSilenceEdits(
                projectId: projectId,
                options: options
            )

            // Wait for job completion
            await waitForJobCompletion(jobId: jobId, aiService: aiService)

            // Reload suggestions
            await loadSuggestions(for: projectId)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func generateChapterSuggestions(for projectId: ProjectId) async {
        isLoading = true
        loadingMessage = "Analyzing transcript for chapters..."
        errorMessage = nil

        do {
            let library = ProjectLibrary()
            let aiService = try await library.getAIService()

            // Use default chapter suggestion options
            let options = ChapterSuggestionOptions.default

            let jobId = try await aiService.suggestChapters(
                projectId: projectId,
                options: options
            )

            // Wait for job completion
            await waitForJobCompletion(jobId: jobId, aiService: aiService)

            // Reload suggestions
            await loadSuggestions(for: projectId)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func deleteSuggestion(_ suggestionId: UUID) async {
        // Remove from array
        suggestions.removeAll { $0.id == suggestionId }

        // Save updated suggestions
        // Note: This is a simplified implementation
        // In production, you'd want to reload from disk to ensure consistency
    }

    private func waitForJobCompletion(jobId: JobId, aiService: AIService) async {
        // Poll for job completion
        let library = ProjectLibrary()
        let jobQueue = try? await library.getJobQueue()

        for _ in 0..<100 { // 10 second timeout
            guard let queue = jobQueue else { break }

            if let job = await queue.getJob(jobId: jobId) {
                switch job.status {
                case .running(let progress):
                    loadingMessage = "Processing... \(Int(progress * 100))%"
                case .success, .failed, .canceled:
                    return
                default:
                    break
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
}

/// Row view for a single suggestion
struct SuggestionRow: View {
    let suggestion: Suggestion
    let onApply: () -> Void
    let onSeek: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            icon
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(suggestion.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    timeLabel
                    confidenceLabel
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button("Seek", action: onSeek)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete suggestion")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var icon: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        switch suggestion.type {
        case .removeSilence:
            return "waveform.path"
        case .createChapter:
            return "bookmark"
        case .suggestCut:
            return "scissors"
        case .suggestOverlay:
            return "pencil"
        case .suggestZoom:
            return "magnifyingglass"
        case .suggestBackground:
            return "photo"
        }
    }

    private var iconColor: Color {
        switch suggestion.type {
        case .removeSilence:
            return .orange
        case .createChapter:
            return .blue
        case .suggestCut:
            return .red
        case .suggestOverlay:
            return .purple
        case .suggestZoom:
            return .green
        case .suggestBackground:
            return .cyan
        }
    }

    private var timeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text("\(String(format: "%.1f", suggestion.timelineIn))s - \(String(format: "%.1f", suggestion.timelineOut))s")
        }
    }

    private var confidenceLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
            Text("\(Int(suggestion.confidence * 100))% confidence")
        }
    }
}

// Note: Preview disabled due to Project initializer not being public in App target
// In production, previews would use a mock project factory
// #Preview {
//     AISuggestionsView(
//         editor: ProjectEditor(project: Project.mock),
//         playheadTime: .constant(0)
//     )
// }
