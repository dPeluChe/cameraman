//
//  ProjectEditorView.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//

import SwiftUI
import EngineKit
import Combine
import CoreGraphics

// MARK: - ViewModel

@MainActor
final class ProjectEditorViewModel: ObservableObject {
    @Published private(set) var editor: ProjectEditor?
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var projectDirectory: URL?
    @Published var mutedTracks: Set<TimelineTrackKind> = []

    let playerViewModel = PreviewPlayerViewModel()

    private let projectId: ProjectId
    private let library: ProjectLibrary
    private var cancellables = Set<AnyCancellable>()

    init(projectId: ProjectId, library: ProjectLibrary = ProjectLibrary.shared) {
        self.projectId = projectId
        self.library = library
        // Defer observer setup to avoid "Publishing changes from within view updates"
        Task { @MainActor [weak self] in
            self?.setupObservers()
        }
    }

    private func setupObservers() {
        NotificationCenter.default.publisher(for: .projectUpdated)
            .compactMap { $0.object as? ProjectId }
            .filter { [weak self] id in id == self?.projectId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadProject()
                }
            }
            .store(in: &cancellables)
    }

    func loadProject() async {
        guard !isLoading else { return }

        // Fetch data outside of view update cycle
        let result: (Project, URL)?
        do {
            let project = try await library.getProject(projectId: projectId)
            let dir = try await library.getProjectDirectory(projectId: projectId)
            result = (project, dir)
        } catch {
            result = nil
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.projectDirectory = nil
                self.isLoading = false
            }
            return
        }

        // Apply all state changes in a single batch via Task to avoid
        // "Publishing changes from within view updates"
        if let (project, dir) = result {
            await MainActor.run {
                self.editor = ProjectEditor(project: project)
                self.projectDirectory = dir
                self.loadError = nil
                self.playerViewModel.seek(to: 0)
                self.isLoading = false
            }
        }
    }
}

// MARK: - Main View

/// Main Project Editor View (Refactored 3-column layout)
struct ProjectEditorView: View {
    let projectSummary: ProjectSummary

    @StateObject private var viewModel: ProjectEditorViewModel
    @State private var showExportModal = false
    @State private var showTranscriptionModal = false
    
    // UI State for DisclosureGroups
    @State private var isLayoutExpanded = true
    @State private var isFormatExpanded = true
    @State private var isCameraExpanded = true
    @State private var isBackgroundExpanded = false
    @State private var isZoomExpanded = false
    @State private var isOverlaysExpanded = false
    @State private var isExportExpanded = true

    init(projectSummary: ProjectSummary, library: ProjectLibrary = ProjectLibrary.shared) {
        self.projectSummary = projectSummary
        _viewModel = StateObject(wrappedValue: ProjectEditorViewModel(projectId: projectSummary.projectId, library: library))
    }

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left panel - Project/Assets
                if let editor = viewModel.editor {
                    LeftPanel(editor: editor)
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                } else {
                    Color(NSColor.controlBackgroundColor)
                        .frame(minWidth: 200, maxWidth: 300)
                }

                // Center - Preview & Timeline
                CenterPanel(
                    viewModel: viewModel,
                    playerViewModel: viewModel.playerViewModel,
                    showExportModal: $showExportModal,
                    showTranscriptionModal: $showTranscriptionModal
                )
                .frame(minWidth: 400)

                // Right panel - Inspector
                if let editor = viewModel.editor {
                    RightPanel(
                        editor: editor,
                        isLayoutExpanded: $isLayoutExpanded,
                        isFormatExpanded: $isFormatExpanded,
                        isCameraExpanded: $isCameraExpanded,
                        isBackgroundExpanded: $isBackgroundExpanded,
                        isZoomExpanded: $isZoomExpanded,
                        isOverlaysExpanded: $isOverlaysExpanded,
                        isExportExpanded: $isExportExpanded,
                        showExportModal: $showExportModal
                    )
                    .frame(minWidth: 260, idealWidth: 280, maxWidth: 360)
                    .clipped()
                } else {
                     Color(NSColor.controlBackgroundColor)
                        .frame(minWidth: 280, maxWidth: 400)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Yield to avoid view update issues
            await Task.yield()
            await viewModel.loadProject()
        }
        .sheet(isPresented: $showExportModal) {
            if let editor = viewModel.editor,
               let projectDirectory = viewModel.projectDirectory {
                ExportView(
                    project: editor.project,
                    projectDirectory: projectDirectory,
                    mutedTracks: viewModel.mutedTracks,
                    onExportComplete: { _ in
                        showExportModal = false
                    },
                    onCancel: {
                        showExportModal = false
                    }
                )
            } else {
                ProgressView()
                    .frame(width: 560, height: 400)
            }
        }
        .sheet(isPresented: $showTranscriptionModal) {
            if let editor = viewModel.editor {
                TranscriptionView(editor: editor, playheadTime: Binding(
                    get: { viewModel.playerViewModel.currentTime },
                    set: { viewModel.playerViewModel.seek(to: $0) }
                ))
            } else {
                ProgressView()
                    .frame(width: 560, height: 400)
            }
        }
    }
}
