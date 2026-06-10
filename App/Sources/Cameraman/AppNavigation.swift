//
//  AppNavigation.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Combine
import SwiftUI
import EngineKit

@MainActor
struct AppNavigation: View {
    @StateObject private var viewModel: AppNavigationViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showHelpPopover = false
    @State private var renameCandidate: ProjectSummary?
    @State private var deleteCandidate: ProjectSummary?
    @State private var renameText = ""
    @State private var tagsCandidate: ProjectSummary?
    @State private var tagsText = ""
    @State private var mergeCandidate: ProjectSummary?

    init(viewModel: AppNavigationViewModel = AppNavigationViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        splitView
            .task {
                await Task.yield()
                await viewModel.loadProjects()
            }
            .toolbar {
                toolbarContent
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecordingWindow)) { notification in
                if let projectId = notification.userInfo?["projectId"] as? ProjectId,
                   let recViewModel = RecordingStateManager.shared.viewModel {
                    recViewModel.targetProjectId = projectId
                }
                openWindow(id: WindowID.recordingControls)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProject)) { notification in
                guard let projectId = notification.object as? ProjectId else { return }
                // Set selection immediately so the detail pane opens without a race condition
                viewModel.selectedItem = .project(projectId)
                NSApp.activate(ignoringOtherApps: true)
                Task { await viewModel.loadProjects() }
            }
            // Removed onAppear auto-open to prevent double windows
    }

    private var splitView: some View {
        projectAlerts(for: splitViewBase)
            .frame(minWidth: 1080, minHeight: 720)
            .sheet(item: $mergeCandidate) { source in
                MergeProjectSheet(
                    source: source,
                    candidates: viewModel.projects.filter { $0.projectId != source.projectId }
                ) { other in
                    Task { await viewModel.mergeProjects(source.projectId, with: other.projectId) }
                }
            }
    }

    private var splitViewBase: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detail
        }
    }

    private func projectAlerts(for view: some View) -> some View {
        view
            .alert("Rename Project", isPresented: renameAlertBinding, presenting: renameCandidate) { project in
                TextField("Project name", text: $renameText)

                Button("Save") {
                    // Capture before the Task runs: dismissing the alert resets
                    // renameText to "" and the async read would see the empty value.
                    let newName = renameText
                    Task {
                        await viewModel.renameProject(projectId: project.projectId, to: newName)
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
                    let tags = AppNavigationViewModel.parseTagsInput(tagsText)
                    Task {
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            Menu {
                Button {
                    openWindow(id: WindowID.recordingControls)
                } label: {
                    Label("New Recording...", systemImage: "record.circle")
                }
                Button {
                    Task { await viewModel.createEmptyProject() }
                } label: {
                    Label("New Empty Project", systemImage: "rectangle.dashed")
                }
                Divider()
                Button {
                    Task { await viewModel.importProjectBundle() }
                } label: {
                    Label("Import Project...", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("New Project", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showHelpPopover = true
            } label: {
                Label("About", systemImage: "questionmark.circle")
            }
            .popover(isPresented: $showHelpPopover, arrowEdge: .bottom) {
                HelpPopoverView()
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

    private var sidebar: some View {
        List(selection: $viewModel.selectedItem) {
            Section("Capture") {
                Button {
                    openWindow(id: WindowID.recordingControls)
                } label: {
                    Label("New Recording", systemImage: "record.circle")
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }

            Section("Projects") {
                // Search and Filter Controls
                VStack(spacing: 8) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))

                        TextField("Search", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)

                        if !viewModel.searchText.isEmpty {
                            Button {
                                viewModel.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(8)

                    // Sort and filter controls
                    HStack(spacing: 8) {
                        // Sort picker
                        Menu {
                            ForEach(ProjectSortOption.allCases, id: \.self) { option in
                                Button {
                                    viewModel.setSortOption(option)
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if viewModel.sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 12))
                                Text(viewModel.sortOption.rawValue)
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        // Sort direction toggle
                        Button {
                            viewModel.toggleSortDirection()
                        } label: {
                            Image(systemName: viewModel.sortDirectionAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Clear filters button
                        if !viewModel.searchText.isEmpty || viewModel.selectedTagFilter != nil {
                            Button("Clear") {
                                viewModel.clearFilters()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                        }
                    }

                    // Tag filter
                    if !viewModel.allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                TagFilterButton(
                                    title: "All",
                                    isSelected: viewModel.selectedTagFilter == nil
                                ) {
                                    viewModel.setTagFilter(nil)
                                }

                                ForEach(viewModel.allTags, id: \.self) { tag in
                                    TagFilterButton(
                                        title: tag,
                                        isSelected: viewModel.selectedTagFilter == tag
                                    ) {
                                        viewModel.setTagFilter(tag)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 8)

                // Project list or grid
                if viewModel.filteredProjects.isEmpty {
                    Text(viewModel.searchText.isEmpty && viewModel.selectedTagFilter == nil
                         ? "No projects yet"
                         : "No matching projects")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    switch viewModel.libraryLayout {
                    case .list:
                        ForEach(viewModel.filteredProjects) { project in
                            ProjectSummaryRow(project: project)
                                .tag(AppNavigationItem.project(project.projectId))
                                .contextMenu {
                                    projectContextMenu(for: project)
                                }
                        }
                    case .grid:
                        ProjectGridView(
                            projects: viewModel.filteredProjects,
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
            EmptyStateView(message: "Start a new recording from the toolbar or sidebar.")
                .overlay {
                    Button("Open Recording Controls") {
                        openWindow(id: WindowID.recordingControls)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 100) // Push below the icon/text
                }
        case .project(let projectId):
            Group {
                if let project = viewModel.project(for: projectId) {
                    ProjectEditorView(projectSummary: project)
                        .id(projectId)
                } else {
                    ProgressView("Loading project...")
                        .task {
                            await viewModel.loadProjects()
                        }
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

        Button("Duplicate") {
            Task { await viewModel.duplicateProject(projectId: project.projectId) }
        }

        Button("Merge Into New Project...") {
            mergeCandidate = project
        }
        .disabled(viewModel.projects.count < 2)

        Button("Export Bundle...") {
            Task { await viewModel.exportProjectBundle(projectId: project.projectId) }
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

