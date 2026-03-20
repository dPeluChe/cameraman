//
//  AISuggestionsViewModel.swift
//  App
//
//  Extracted from AISuggestionsView.swift
//  View model and suggestion row for AI suggestions
//

import Combine
import SwiftUI
import EngineKit

/// View model for AI Suggestions
@MainActor
final class AISuggestionsViewModel: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published private(set) var errorMessage: String?

    private let projectLibrary = ProjectLibrary.shared

    func loadSuggestions(for projectId: ProjectId) async {
        isLoading = true
        loadingMessage = "Loading suggestions..."
        errorMessage = nil

        do {
            let projectDirectory = try await projectLibrary.getProjectDirectory(projectId: projectId)
            let suggestionsPath = projectDirectory.appendingPathComponent("ai_suggestions.json")

            guard FileManager.default.fileExists(atPath: suggestionsPath.path) else {
                suggestions = []
                isLoading = false
                return
            }

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
            let library = ProjectLibrary.shared
            let aiService = try await library.getAIService()

            let options = SilenceDetectionOptions.default

            let jobId = try await aiService.suggestSilenceEdits(
                projectId: projectId,
                options: options
            )

            await waitForJobCompletion(jobId: jobId, aiService: aiService)
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
            let library = ProjectLibrary.shared
            let aiService = try await library.getAIService()

            let options = ChapterSuggestionOptions.default

            let jobId = try await aiService.suggestChapters(
                projectId: projectId,
                options: options
            )

            await waitForJobCompletion(jobId: jobId, aiService: aiService)
            await loadSuggestions(for: projectId)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func deleteSuggestion(_ suggestionId: UUID) async {
        suggestions.removeAll { $0.id == suggestionId }
    }

    private func waitForJobCompletion(jobId: JobId, aiService: AIService) async {
        let library = ProjectLibrary.shared
        let jobQueue = try? await library.getJobQueue()

        for _ in 0..<100 {
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

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - Suggestion Row

/// Row view for a single suggestion
struct SuggestionRow: View {
    let suggestion: Suggestion
    let onApply: () -> Void
    let onSeek: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

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
