//
//  ProjectEditorView.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//

import SwiftUI
import EngineKit
import CoreGraphics

@MainActor
final class ProjectEditorViewModel: ObservableObject {
    @Published private(set) var editor: ProjectEditor?
    @Published var playheadTime: TimeInterval = 0
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var projectDirectory: URL?

    private let projectId: ProjectId
    private let library: ProjectLibrary

    init(projectId: ProjectId, library: ProjectLibrary = ProjectLibrary()) {
        self.projectId = projectId
        self.library = library
    }

    func loadProject() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let project = try await library.getProject(projectId: projectId)
            let projectDirectory = try await library.getProjectDirectory(projectId: projectId)
            editor = ProjectEditor(project: project)
            self.projectDirectory = projectDirectory
            loadError = nil
            playheadTime = 0
        } catch {
            loadError = error.localizedDescription
            projectDirectory = nil
        }
    }
}

struct ProjectEditorView: View {
    let projectSummary: ProjectSummary

    @StateObject private var viewModel: ProjectEditorViewModel
    @State private var showExportModal: Bool = false

    init(projectSummary: ProjectSummary, library: ProjectLibrary = ProjectLibrary()) {
        self.projectSummary = projectSummary
        _viewModel = StateObject(wrappedValue: ProjectEditorViewModel(projectId: projectSummary.projectId, library: library))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Divider()

            PreviewPlayerView(project: viewModel.editor?.project, projectDirectory: viewModel.projectDirectory)

            if let editor = viewModel.editor {
                LayoutSelectorView(editor: editor)
                if editor.project.canvas.layout.type == CanvasLayout.LayoutPreset.pip.rawValue,
                   editor.project.sources.camera != nil,
                   editor.project.canvas.layout.camera != nil {
                    PiPConfigurationView(editor: editor)
                }
                BackgroundControlsView(editor: editor)
                OverlayEditorView(editor: editor, playheadTime: $viewModel.playheadTime)
                TimelineView(editor: editor, playheadTime: $viewModel.playheadTime)
            } else if viewModel.isLoading {
                ProgressView("Loading project timeline...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(viewModel.loadError ?? "Unable to load the project.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.loadProject()
        }
        .sheet(isPresented: $showExportModal) {
            if let editor = viewModel.editor,
               let projectDirectory = viewModel.projectDirectory {
                ExportView(
                    project: editor.project,
                    projectDirectory: projectDirectory,
                    onExportComplete: { url in
                        showExportModal = false
                        if let url = url {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    },
                    onCancel: {
                        showExportModal = false
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(projectSummary.name)
                    .font(.largeTitle)

                HStack(spacing: 12) {
                    Label(ProjectEditorView.durationText(for: projectSummary.duration), systemImage: "clock")
                    Label(ProjectEditorView.dateText(for: projectSummary.updatedAt), systemImage: "calendar")
                }
                .foregroundStyle(.secondary)

                if !projectSummary.tags.isEmpty {
                    Text("Tags: \(projectSummary.tags.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showExportModal = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.editor == nil)
        }
    }

    private static func durationText(for duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func dateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct LayoutSelectorView: View {
    @ObservedObject var editor: ProjectEditor

    private let presets: [CanvasLayout.LayoutPreset] = [.fullscreen, .pip, .sideBySide]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(presets, id: \.self) { preset in
                    LayoutPresetButton(
                        preset: preset,
                        isSelected: preset == selectedPreset,
                        isEnabled: isPresetEnabled(preset)
                    ) {
                        Task {
                            _ = await editor.setLayoutPreset(preset)
                        }
                    }
                }
            }
        }
    }

    private var selectedPreset: CanvasLayout.LayoutPreset {
        CanvasLayout.LayoutPreset(rawValue: editor.project.canvas.layout.type) ?? .fullscreen
    }

    private func isPresetEnabled(_ preset: CanvasLayout.LayoutPreset) -> Bool {
        preset == .fullscreen || editor.project.sources.camera != nil
    }
}

private struct LayoutPresetButton: View {
    let preset: CanvasLayout.LayoutPreset
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LayoutPreview(preset: preset)
                    .frame(width: 92, height: 56)

                Text(label)
                    .font(.subheadline)
            }
            .padding(10)
            .frame(minWidth: 110)
            .background(backgroundShape.fill(Color.primary.opacity(isSelected ? 0.12 : 0.04)))
            .overlay(
                backgroundShape.stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    private var label: String {
        switch preset {
        case .fullscreen:
            return "Full"
        case .pip:
            return "PiP"
        case .sideBySide:
            return "Side-by-Side"
        case .cinematic:
            return "Cinematic"
        }
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

private struct LayoutPreview: View {
    let preset: CanvasLayout.LayoutPreset

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let canvas = RoundedRectangle(cornerRadius: 6, style: .continuous)
            let screenFill = Color.primary.opacity(0.16)
            let accentFill = Color.accentColor.opacity(0.55)

            ZStack {
                canvas.fill(Color.primary.opacity(0.04))
                canvas.stroke(Color.primary.opacity(0.2), lineWidth: 1)

                switch preset {
                case .fullscreen:
                    canvas.fill(screenFill).padding(3)
                case .pip:
                    canvas.fill(screenFill).padding(3)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accentFill)
                        .frame(width: size.width * 0.32, height: size.height * 0.32)
                        .position(x: size.width * 0.74, y: size.height * 0.74)
                case .sideBySide:
                    HStack(spacing: size.width * 0.04) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(screenFill)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accentFill)
                    }
                    .padding(4)
                case .cinematic:
                    canvas.fill(screenFill).padding(3)
                }
            }
        }
    }
}

private struct PiPConfigurationView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var cornerSnapshot: Project?

    var body: some View {
        if let camera = editor.project.canvas.layout.camera {
            let format = editor.project.canvas.format
            let aspectRatio = Double(format.w) / Double(format.h)

            VStack(alignment: .leading, spacing: 12) {
                Text("PiP Camera")
                    .font(.headline)

                HStack(alignment: .top, spacing: 16) {
                    PiPCanvasEditor(
                        editor: editor,
                        camera: camera,
                        aspectRatio: aspectRatio
                    )
                    .frame(width: 260)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Presets")
                                .font(.subheadline)

                            HStack(spacing: 8) {
                                ForEach(PiPPreset.allCases, id: \.self) { preset in
                                    Button(preset.rawValue) {
                                        let updated = PiPLayoutHelper.presetPosition(preset, camera: camera)
                                        Task {
                                            _ = await editor.updateCameraPosition(updated, recordUndoFrom: editor.project)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Corner Radius")
                                .font(.subheadline)

                            Slider(
                                value: Binding(
                                    get: { camera.cornerRadius },
                                    set: { newValue in
                                        var updated = camera
                                        updated.cornerRadius = newValue
                                        Task {
                                            _ = await editor.updateCameraPosition(updated)
                                        }
                                    }
                                ),
                                in: 0...40,
                                onEditingChanged: { isEditing in
                                    if isEditing {
                                        cornerSnapshot = editor.project
                                    } else if let snapshot = cornerSnapshot,
                                              let currentCamera = editor.project.canvas.layout.camera {
                                        Task {
                                            _ = await editor.updateCameraPosition(currentCamera, recordUndoFrom: snapshot)
                                        }
                                        cornerSnapshot = nil
                                    }
                                }
                            )
                            .frame(maxWidth: 180)
                        }
                    }
                }
            }
        }
    }
}

private struct PiPCanvasEditor: View {
    @ObservedObject var editor: ProjectEditor
    let camera: Project.Canvas.Layout.CameraPosition
    let aspectRatio: Double

    @State private var dragStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var dragSnapshot: Project?
    @State private var resizeStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var resizeSnapshot: Project?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = editor.project.canvas.layout
            let cameraFrame = CanvasLayout.calculateCameraFrame(
                layout: layout,
                canvasWidth: Int(size.width),
                canvasHeight: Int(size.height)
            ) ?? .zero

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .padding(6)

                RoundedRectangle(cornerRadius: max(2, camera.cornerRadius), style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: cameraFrame.width, height: cameraFrame.height)
                    .position(x: cameraFrame.midX, y: cameraFrame.midY)
                    .overlay(
                        RoundedRectangle(cornerRadius: max(2, camera.cornerRadius), style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .gesture(moveGesture(in: size))

                ForEach(PiPHandle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .position(handlePosition(handle, frame: cameraFrame))
                        .gesture(resizeGesture(for: handle, in: size))
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func handlePosition(_ handle: PiPHandle, frame: CoreFoundation.CGRect) -> CoreFoundation.CGPoint {
        switch handle {
        case .topLeft:
            return CoreFoundation.CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            return CoreFoundation.CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            return CoreFoundation.CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            return CoreFoundation.CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func moveGesture(in size: CoreGraphics.CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragStartCamera ?? camera
                if dragStartCamera == nil {
                    dragStartCamera = camera
                    dragSnapshot = editor.project
                }

                let updated = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                Task {
                    _ = await editor.updateCameraPosition(updated)
                }
            }
            .onEnded { value in
                let base = dragStartCamera ?? camera
                let updated = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                if let snapshot = dragSnapshot {
                    Task {
                        _ = await editor.updateCameraPosition(updated, recordUndoFrom: snapshot)
                    }
                }
                dragStartCamera = nil
                dragSnapshot = nil
            }
    }

    private func resizeGesture(for handle: PiPHandle, in size: CoreGraphics.CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = resizeStartCamera ?? camera
                if resizeStartCamera == nil {
                    resizeStartCamera = camera
                    resizeSnapshot = editor.project
                }

                let updated = PiPLayoutHelper.resized(
                    camera: base,
                    handle: handle,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                Task {
                    _ = await editor.updateCameraPosition(updated)
                }
            }
            .onEnded { value in
                let base = resizeStartCamera ?? camera
                let updated = PiPLayoutHelper.resized(
                    camera: base,
                    handle: handle,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                if let snapshot = resizeSnapshot {
                    Task {
                        _ = await editor.updateCameraPosition(updated, recordUndoFrom: snapshot)
                    }
                }
                resizeStartCamera = nil
                resizeSnapshot = nil
            }
    }
}
