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

    init(projectSummary: ProjectSummary, library: ProjectLibrary = ProjectLibrary()) {
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
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
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
                TranscriptionView(editor: editor, playheadTime: $viewModel.playheadTime)
            } else {
                ProgressView()
                    .frame(width: 560, height: 400)
            }
        }
    }
}

// MARK: - Left Panel (Assets)
private struct LeftPanel: View {
    @ObservedObject var editor: ProjectEditor
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Project Assets")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            
            Divider()
            
            List {
                Section("Sources") {
                    AssetRow(icon: "display", title: "Screen Recording", subtitle: "Main")
                    if editor.project.primarySources?.camera != nil {
                        AssetRow(icon: "video.fill", title: "Camera Feed", subtitle: "1080p")
                    }
                    if editor.project.primarySources?.audio != nil {
                        AssetRow(icon: "mic.fill", title: "Microphone", subtitle: "Audio Track")
                        AssetRow(icon: "speaker.wave.2.fill", title: "System Audio", subtitle: "Audio Track")
                    }
                }
                
                Section("Layers") {
                     ForEach(editor.project.timeline.segments) { segment in
                         AssetRow(icon: "film", title: "Segment \(segment.id.prefix(4))", subtitle: "\(String(format: "%.1f", segment.sourceOut - segment.sourceIn))s")
                     }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct AssetRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Center Panel (Workspace)
private struct CenterPanel: View {
    @ObservedObject var viewModel: ProjectEditorViewModel
    @Binding var showExportModal: Bool
    @Binding var showTranscriptionModal: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            ZStack {
                Color.black
                
                if let editor = viewModel.editor {
                    PreviewPlayerView(
                        project: editor.project,
                        projectDirectory: viewModel.projectDirectory
                    )
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Timeline
            if let editor = viewModel.editor {
                TimelineView(
                    editor: editor,
                    playheadTime: $viewModel.playheadTime,
                    projectDirectory: viewModel.projectDirectory
                )
                .frame(height: 300)
            } else {
                 Color(NSColor.controlBackgroundColor)
                    .frame(height: 300)
            }
        }
    }
}

// MARK: - Right Panel (Inspector)
private struct RightPanel: View {
    @ObservedObject var editor: ProjectEditor
    
    // Binding states for expansion
    @Binding var isLayoutExpanded: Bool
    @Binding var isFormatExpanded: Bool
    @Binding var isCameraExpanded: Bool
    @Binding var isBackgroundExpanded: Bool
    @Binding var isZoomExpanded: Bool
    @Binding var isOverlaysExpanded: Bool
    @Binding var isExportExpanded: Bool
    @Binding var showExportModal: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                Text("Configuration")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                
                Divider()
                
                VStack(spacing: 0) {
                    // Layout Group
                    ConfigGroup(title: "Layout", isExpanded: $isLayoutExpanded) {
                        LayoutSelectorView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Format Group
                    ConfigGroup(title: "Format", isExpanded: $isFormatExpanded) {
                        FormatToggleView(editor: editor)
                    }
                    
                    if editor.project.canvas.layout.camera != nil {
                        Divider()
                        
                        // Camera Group
                        ConfigGroup(title: "Camera", isExpanded: $isCameraExpanded) {
                            PiPConfigurationView(editor: editor)
                        }
                    }
                    
                    Divider()
                    
                    // Background Group
                    ConfigGroup(title: "Background", isExpanded: $isBackgroundExpanded) {
                        BackgroundControlsView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Auto-Zoom Group
                    ConfigGroup(title: "Auto-Zoom", isExpanded: $isZoomExpanded) {
                         ZoomControlsView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Overlays Group
                    ConfigGroup(title: "Overlays", isExpanded: $isOverlaysExpanded) {
                        // Using a playhead constant here since we are just configuring overlay logic, 
                        // but ideally OverlayEditorView needs the binding if it scrubs.
                        // For the inspector, we mostly want the list/add buttons.
                        // We can pass .constant(0) if it's just for property editing, 
                        // or rewire if needed.
                        OverlayEditorView(editor: editor, playheadTime: .constant(0))
                    }
                    
                    Divider()
                    
                    // Export Section (Always visible or in a group)
                    ConfigGroup(title: "Export", isExpanded: $isExportExpanded) {
                        Button {
                            showExportModal = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Video...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct ConfigGroup<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: () -> Content
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 12)
                .padding(.bottom, 16)
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Components

// --- LayoutSelectorView ---

private struct LayoutSelectorView: View {
    @ObservedObject var editor: ProjectEditor

    private let presets: [CanvasLayout.LayoutPreset] = [.fullscreen, .pip, .sideBySide]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        preset == .fullscreen || editor.project.primarySources?.camera != nil
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

// --- FormatToggleView ---

private struct FormatToggleView: View {
    @ObservedObject var editor: ProjectEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FormatButton(
                    title: "16:9",
                    icon: "rectangle.ratio.16.to.9",
                    isSelected: isAspect(.landscape16_9)
                ) {
                    setAspect(.landscape16_9)
                }

                FormatButton(
                    title: "9:16",
                    icon: "rectangle.ratio.9.to.16",
                    isSelected: isAspect(.portrait9_16)
                ) {
                    setAspect(.portrait9_16)
                }

                FormatButton(
                    title: "1:1",
                    icon: "square",
                    isSelected: isAspect(.square1_1)
                ) {
                    setAspect(.square1_1)
                }
            }
        }
    }

    private func isAspect(_ ratio: CanvasLayout.AspectRatio) -> Bool {
        return editor.project.canvas.format.aspect == ratio.rawValue
    }

    private func setAspect(_ ratio: CanvasLayout.AspectRatio) {
        Task {
            _ = await editor.setFormat(ratio)
        }
    }
}

private struct FormatButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(width: 80, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// --- PiPConfigurationView ---

private struct PiPConfigurationView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var cornerSnapshot: Project?

    var body: some View {
        if let camera = editor.project.canvas.layout.camera {
            let format = editor.project.canvas.format
            let aspectRatio = Double(format.w) / Double(format.h)

            VStack(alignment: .leading, spacing: 12) {
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
            let ekCameraFrame = CanvasLayout.calculateCameraFrame(
                layout: layout,
                canvasWidth: Int(size.width),
                canvasHeight: Int(size.height)
            )
            
            let cameraFrame = ekCameraFrame.map { ekFrame in
                CoreGraphics.CGRect(x: CGFloat(ekFrame.minX), y: CGFloat(ekFrame.minY), width: CGFloat(ekFrame.width), height: CGFloat(ekFrame.height))
            } ?? CoreGraphics.CGRect.zero

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

    private func handlePosition(_ handle: PiPHandle, frame: CoreGraphics.CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
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

    private func resizeGesture(for handle: PiPHandle, in size: CGSize) -> some Gesture {
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
