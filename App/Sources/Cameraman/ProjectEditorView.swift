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
    @Published var selectedSegmentId: String?
    @Published var selectedMediaItemId: UUID?
    @Published var selectedOverlayId: UUID?

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

        // Reset player state before loading new project to prevent leaks
        playerViewModel.reset()

        // Fetch data outside of view update cycle
        let result: (Project, URL)?
        do {
            let project = try await library.getProject(projectId: projectId)
            let dir = try await library.getProjectDirectory(projectId: projectId)
            result = (project, dir)
        } catch {
            result = nil
            // Yield so these @Published mutations don't land inside a SwiftUI
            // body update cycle.
            await Task.yield()
            self.loadError = error.localizedDescription
            self.projectDirectory = nil
            self.isLoading = false
            return
        }

        // Yield so these @Published mutations don't land inside a SwiftUI
        // body update cycle.
        if let (project, dir) = result {
            await Task.yield()
            self.editor = ProjectEditor(project: project)
            self.projectDirectory = dir
            self.loadError = nil
            self.playerViewModel.seek(to: 0)
            self.isLoading = false
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
    @State private var showAISuggestionsModal = false
    
    // UI State for DisclosureGroups
    @State private var isLayoutExpanded = true
    @State private var isFormatExpanded = true
    @State private var isCameraExpanded = true
    @State private var isVideoEffectsExpanded = false
    @State private var isBackgroundExpanded = false
    @State private var isZoomExpanded = false
    @State private var isCursorExpanded = false
    @State private var isOverlaysExpanded = false
    @State private var isExportExpanded = true
    @State private var isAssetsExpanded = true

    init(projectSummary: ProjectSummary, library: ProjectLibrary = ProjectLibrary.shared) {
        self.projectSummary = projectSummary
        _viewModel = StateObject(wrappedValue: ProjectEditorViewModel(projectId: projectSummary.projectId, library: library))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let editor = viewModel.editor {
                ProjectAssetsBar(editor: editor, isExpanded: $isAssetsExpanded)
            } else {
                Color(NSColor.controlBackgroundColor)
                    .frame(height: 38)
            }

            Divider()

            HSplitView {
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
                        selectedSegmentId: viewModel.selectedSegmentId,
                        selectedMediaItemId: viewModel.selectedMediaItemId,
                        selectedOverlayId: $viewModel.selectedOverlayId,
                        playerViewModel: viewModel.playerViewModel,
                        isLayoutExpanded: $isLayoutExpanded,
                        isFormatExpanded: $isFormatExpanded,
                        isCameraExpanded: $isCameraExpanded,
                        isVideoEffectsExpanded: $isVideoEffectsExpanded,
                        isBackgroundExpanded: $isBackgroundExpanded,
                        isZoomExpanded: $isZoomExpanded,
                        isCursorExpanded: $isCursorExpanded,
                        isOverlaysExpanded: $isOverlaysExpanded,
                        isExportExpanded: $isExportExpanded,
                        showExportModal: $showExportModal,
                        showTranscriptionModal: $showTranscriptionModal,
                        showAISuggestionsModal: $showAISuggestionsModal
                    )
                    .frame(width: 300)
                    .clipped()
                } else {
                     Color(NSColor.controlBackgroundColor)
                        .frame(width: 300)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .toast(Binding(
            get: { viewModel.editor?.showAutosaveToast ?? false },
            set: { viewModel.editor?.showAutosaveToast = $0 }
        ), message: "Project saved")
        .task {
            // Yield to avoid view update issues
            await Task.yield()
            await viewModel.loadProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExportModal)) { _ in
            if viewModel.editor != nil, viewModel.projectDirectory != nil {
                showExportModal = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTranscriptionModal)) { _ in
            if viewModel.editor != nil { showTranscriptionModal = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAISuggestions)) { _ in
            if viewModel.editor != nil { showAISuggestionsModal = true }
        }
        .sheet(isPresented: $showExportModal) {
            if let editor = viewModel.editor,
               let projectDirectory = viewModel.projectDirectory {
                ExportView(
                    project: editor.project,
                    projectDirectory: projectDirectory,
                    mutedTracks: viewModel.mutedTracks,
                    zoomPlan: viewModel.playerViewModel.computeEffectiveZoomPlan(),
                    cursorPlan: viewModel.playerViewModel.computeEffectiveCursorPlan(),
                    onExportComplete: { _ in
                        showExportModal = false
                    },
                    onCancel: {
                        showExportModal = false
                    }
                )
            } else {
                ProgressView()
                    .frame(minWidth: 460, idealWidth: 560, minHeight: 360, idealHeight: 440)
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
        .sheet(isPresented: $showAISuggestionsModal) {
            if let editor = viewModel.editor {
                AISuggestionsView(editor: editor)
            } else {
                ProgressView()
                    .frame(width: 600, height: 500)
            }
        }
    }
}
