//
//  AppNavigation.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI
import EngineKit

enum AppNavigationItem: Hashable {
    case recording
    case project(ProjectId)
}

enum ProjectLibraryLayout: String, CaseIterable {
    case list
    case grid
}

@MainActor
final class AppNavigationViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectSummary] = []
    @Published var selectedItem: AppNavigationItem = .recording
    @Published private(set) var loadErrorMessage: String?
    @Published var libraryLayout: ProjectLibraryLayout = .list

    private let library: ProjectLibrary

    nonisolated init(library: ProjectLibrary = ProjectLibrary()) {
        self.library = library
    }

    func loadProjects() async {
        do {
            let loadedProjects = try await library.listProjects()
            projects = loadedProjects
            loadErrorMessage = nil

            if case let .project(projectId) = selectedItem,
               !loadedProjects.contains(where: { $0.projectId == projectId }) {
                selectedItem = .recording
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func project(for projectId: ProjectId) -> ProjectSummary? {
        projects.first { $0.projectId == projectId }
    }

    func renameProject(projectId: ProjectId, to newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            loadErrorMessage = "Project name can't be empty."
            return
        }

        do {
            try await library.renameProject(projectId: projectId, to: trimmedName)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func deleteProject(projectId: ProjectId) async {
        do {
            try await library.deleteProject(projectId: projectId)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func setTags(projectId: ProjectId, tags: [String]) async {
        let cleanedTags = Self.normalizeTags(tags)
        do {
            try await library.setTags(projectId: projectId, tags: cleanedTags)
            await loadProjects()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    static func parseTagsInput(_ input: String) -> [String] {
        let tokens = input.split(separator: ",")
        return normalizeTags(tokens.map { String($0) })
    }

    private static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    func clearError() {
        loadErrorMessage = nil
    }

    func toggleLibraryLayout() {
        libraryLayout = libraryLayout == .list ? .grid : .list
    }
}

@MainActor
struct AppNavigation: View {
    @StateObject private var viewModel: AppNavigationViewModel
    @State private var renameCandidate: ProjectSummary?
    @State private var deleteCandidate: ProjectSummary?
    @State private var renameText = ""
    @State private var tagsCandidate: ProjectSummary?
    @State private var tagsText = ""

    init(viewModel: AppNavigationViewModel = AppNavigationViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task {
            await viewModel.loadProjects()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        await viewModel.loadProjects()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.selectedItem = .recording
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.toggleLibraryLayout()
                } label: {
                    Label(
                        viewModel.libraryLayout == .list ? "Grid View" : "List View",
                        systemImage: viewModel.libraryLayout == .list ? "square.grid.2x2" : "list.bullet"
                    )
                }
            }
        }
        .alert("Rename Project", isPresented: renameAlertBinding, presenting: renameCandidate) { project in
            TextField("Project name", text: $renameText)

            Button("Save") {
                Task {
                    await viewModel.renameProject(projectId: project.projectId, to: renameText)
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Enter a new name for the project.")
        }
        .alert("Edit Tags", isPresented: tagsAlertBinding, presenting: tagsCandidate) { project in
            TextField("Tags (comma separated)", text: $tagsText)

            Button("Save") {
                Task {
                    let tags = AppNavigationViewModel.parseTagsInput(tagsText)
                    await viewModel.setTags(projectId: project.projectId, tags: tags)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Add tags separated by commas. Leave empty to clear tags.")
        }
        .alert("Delete Project", isPresented: deleteAlertBinding, presenting: deleteCandidate) { project in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteProject(projectId: project.projectId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("This will permanently delete \"\(project.name)\".")
        }
        .alert("Project Library Error", isPresented: Binding(get: {
            viewModel.loadErrorMessage != nil
        }, set: { newValue in
            if !newValue {
                viewModel.clearError()
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.loadErrorMessage ?? "Unknown error.")
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedItem) {
            Section("Capture") {
                Label("New Recording", systemImage: "record.circle")
                    .tag(AppNavigationItem.recording)
            }

            Section("Projects") {
                if viewModel.projects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                } else {
                    switch viewModel.libraryLayout {
                    case .list:
                        ForEach(viewModel.projects) { project in
                            ProjectSummaryRow(project: project)
                                .tag(AppNavigationItem.project(project.projectId))
                                .contextMenu {
                                    projectContextMenu(for: project)
                                }
                        }
                    case .grid:
                        ProjectGridView(
                            projects: viewModel.projects,
                            selectedItem: viewModel.selectedItem,
                            onSelect: { projectId in
                                viewModel.selectedItem = .project(projectId)
                            },
                            contextMenu: { project in
                                projectContextMenu(for: project)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .navigationTitle("Project Studio")
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedItem {
        case .recording:
            RecordingControlView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
        case .project(let projectId):
            Group {
                if let project = viewModel.project(for: projectId) {
                    ProjectEditorView(projectSummary: project)
                } else {
                    EmptyStateView(message: "Select a project to start editing.")
                }
            }
        }
    }
}

private extension AppNavigation {
    @ViewBuilder
    func projectContextMenu(for project: ProjectSummary) -> some View {
        Button("Open") {
            viewModel.selectedItem = .project(project.projectId)
        }

        Button("Rename") {
            renameCandidate = project
            renameText = project.name
        }

        Button("Edit Tags") {
            tagsCandidate = project
            tagsText = project.tags.joined(separator: ", ")
        }

        Divider()

        Button("Delete", role: .destructive) {
            deleteCandidate = project
        }
    }

    var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameCandidate != nil },
            set: { newValue in
                if !newValue {
                    renameCandidate = nil
                    renameText = ""
                }
            }
        )
    }

    var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { newValue in
                if !newValue {
                    deleteCandidate = nil
                }
            }
        )
    }

    var tagsAlertBinding: Binding<Bool> {
        Binding(
            get: { tagsCandidate != nil },
            set: { newValue in
                if !newValue {
                    tagsCandidate = nil
                    tagsText = ""
                }
            }
        )
    }
}

private struct ProjectSummaryRow: View {
    let project: ProjectSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectThumbnailView(thumbnailPath: project.thumbnailPath)
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(formattedUpdatedAt) • \(formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !project.tags.isEmpty {
                    Text(project.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedUpdatedAt: String {
        ProjectSummaryFormatting.dateFormatter.string(from: project.updatedAt)
    }

    private var formattedDuration: String {
        let totalSeconds = Int(project.duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static let dateFormatter = ProjectSummaryFormatting.dateFormatter
}

private struct ProjectGridView<ContextMenu: View>: View {
    let projects: [ProjectSummary]
    let selectedItem: AppNavigationItem
    let onSelect: (ProjectId) -> Void
    let contextMenu: (ProjectSummary) -> ContextMenu

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(projects) { project in
                Button {
                    onSelect(project.projectId)
                } label: {
                    ProjectSummaryCard(
                        project: project,
                        isSelected: isSelected(project.projectId)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    contextMenu(project)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func isSelected(_ projectId: ProjectId) -> Bool {
        if case let .project(selectedId) = selectedItem {
            return selectedId == projectId
        }
        return false
    }
}

private struct ProjectSummaryCard: View {
    let project: ProjectSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProjectThumbnailView(thumbnailPath: project.thumbnailPath)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(project.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("\(formattedUpdatedAt) • \(formattedDuration)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !project.tags.isEmpty {
                Text(project.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var formattedUpdatedAt: String {
        ProjectSummaryFormatting.dateFormatter.string(from: project.updatedAt)
    }

    private var formattedDuration: String {
        let totalSeconds = Int(project.duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private enum ProjectSummaryFormatting {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
