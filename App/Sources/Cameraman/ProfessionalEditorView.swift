//
//  ProfessionalEditorView.swift
//  Cameraman
//
//  Created by Droid on 2026-01-21.
//  Professional video editing interface with improved layout
//

import SwiftUI
import EngineKit

/// Professional video editor with three-panel layout
struct ProfessionalEditorView: View {
    let projectSummary: ProjectSummary

    @StateObject private var viewModel: ProjectEditorViewModel
    @State private var selectedTool: EditorTool = .select
    @State private var showExportModal = false
    @State private var showTranscriptionModal = false
    @State private var leftPanelWidth: CGFloat = 280
    @State private var rightPanelWidth: CGFloat = 320

    enum EditorTool: String, CaseIterable {
        case select = "cursorarrow"
        case trim = "scissors"
        case text = "textformat"
        case arrow = "arrowshape.turn.up.left"
        case rectangle = "rectangle"
        case zoom = "magnifyingglass"

        var label: String {
            switch self {
            case .select: return "Select"
            case .trim: return "Trim"
            case .text: return "Text"
            case .arrow: return "Arrow"
            case .rectangle: return "Rectangle"
            case .zoom: return "Zoom"
            }
        }
    }

    init(projectSummary: ProjectSummary) {
        self.projectSummary = projectSummary
        _viewModel = StateObject(wrappedValue: ProjectEditorViewModel(projectId: projectSummary.projectId))
    }

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left panel - Tools & Properties
                leftPanel
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

                // Center - Preview & Timeline
                centerPanel

                // Right panel - Layers & Effects
                rightPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.loadProject()
        }
        .sheet(isPresented: $showExportModal) {
            // Export modal
        }
        .sheet(isPresented: $showTranscriptionModal) {
            // Transcription modal
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Project header
            projectHeader

            Divider()

            // Tools section
            toolsSection

            Divider()

            // Properties section
            propertiesSection

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(projectSummary.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text("\(formattedDuration) • \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("Export...") { showExportModal = true }
                    Button("Transcript") { showTranscriptionModal = true }
                    Divider()
                    Button("Project Settings") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            if !projectSummary.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(projectSummary.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(Color.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)

            LazyVGrid(columns: [GridItem(.flexible(minimum: 60))], spacing: 8) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool
                    ) {
                        selectedTool = tool
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
    }

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)

            // Context-aware properties based on selected tool
            propertiesContent
                .padding(.horizontal)
        }
        .padding(.bottom)
    }

    @ViewBuilder
    private var propertiesContent: some View {
        switch selectedTool {
        case .select:
            Text("Select an object to edit its properties")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical)

        case .trim:
            trimProperties

        case .text:
            textProperties

        case .arrow, .rectangle:
            shapeProperties

        case .zoom:
            zoomProperties
        }
    }

    private var trimProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            PropertyRow(label: "Start Time", value: "00:00.000")
            PropertyRow(label: "End Time", value: "01:23.456")
            PropertyRow(label: "Duration", value: "01:23.456")

            Divider()

            Button("Split at Playhead") {
                // Split functionality
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button("Delete Selection") {
                // Delete functionality
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
    }

    private var textProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Text", text: .constant("Sample Text"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Font")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Font", selection: .constant("SF Pro")) {
                    Text("SF Pro").tag("SF Pro")
                    Text("Helvetica").tag("Helvetica")
                    Text("Arial").tag("Arial")
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: .constant(48), in: 12...144, step: 1)
                Text("48 pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                ColorPicker("Fill", selection: .constant(Color.white))
                ColorPicker("Stroke", selection: .constant(Color.black))
            }
        }
    }

    private var shapeProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ColorPicker("Fill", selection: .constant(Color.red))
                Spacer()
            }

            HStack {
                ColorPicker("Stroke", selection: .constant(Color.white))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Stroke Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: .constant(3), in: 0...20, step: 1)
                Text("3 px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Shadow", isOn: .constant(true))
        }
    }

    private var zoomProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto Zoom", isOn: .constant(true))

            VStack(alignment: .leading, spacing: 8) {
                Text("Intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Intensity", selection: .constant(1)) {
                    Text("Subtle").tag(0)
                    Text("Normal").tag(1)
                    Text("Aggressive").tag(2)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Center Panel

    private var centerPanel: some View {
        VStack(spacing: 0) {
            // Preview area
            previewArea

            Divider()

            // Timeline
            if let editor = viewModel.editor {
                TimelineView(
                    editor: editor,
                    playheadTime: .constant(0),
                    projectDirectory: viewModel.projectDirectory
                )
            } else if viewModel.isLoading {
                ProgressView("Loading timeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var previewArea: some View {
        ZStack {
            if let editor = viewModel.editor {
                PreviewPlayerView(
                    project: editor.project,
                    projectDirectory: viewModel.projectDirectory
                )
            } else {
                ProgressView()
            }
        }
        .frame(minHeight: 300)
        .background(Color.black)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Panel", selection: .constant(0)) {
                Text("Layers").tag(0)
                Text("Effects").tag(1)
                Text("Layout").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Panel content
            tabContent

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var tabContent: some View {
        layersContent
    }

    private var layersContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)

            VStack(spacing: 6) {
                LayerRow(icon: "display", label: "Screen Recording", isVisible: true, isLocked: false)
                LayerRow(icon: "video", label: "Camera", isVisible: true, isLocked: false)
                LayerRow(icon: "speaker.wave.2", label: "System Audio", isVisible: true, isLocked: false)
                LayerRow(icon: "mic", label: "Microphone", isVisible: true, isLocked: false)

                Divider()
                    .padding(.vertical, 4)

                LayerRow(icon: "arrow.up.forward", label: "Arrow 1", isVisible: true, isLocked: false)
                LayerRow(icon: "rectangle", label: "Rectangle 1", isVisible: true, isLocked: false)
                LayerRow(icon: "textformat", label: "Text 1", isVisible: false, isLocked: false)
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
    }

    private var effectsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)

            EffectRow(label: "Background Blur", value: .constant(0))
            EffectRow(label: "Color Adjust", value: .constant(0))
            EffectRow(label: "Brightness", value: .constant(50))
            EffectRow(label: "Contrast", value: .constant(50))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var layoutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canvas Layout")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)

            // Layout options simplified for now
            VStack(alignment: .leading, spacing: 8) {
                Text("Layout Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    layoutPresetButton("Full Screen", isSelected: true)
                    layoutPresetButton("PiP", isSelected: false)
                    layoutPresetButton("Side-by-Side", isSelected: false)
                }
            }

            // Format toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    formatButton("16:9", isSelected: true)
                    formatButton("9:16", isSelected: false)
                }
            }

            Spacer()
        }
        .padding(.bottom)
    }

    private func layoutPresetButton(_ title: String, isSelected: Bool) -> some View {
        Button {

        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func formatButton(_ title: String, isSelected: Bool) -> some View {
        Button {

        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Views

    private struct ToolButton: View {
        let tool: EditorTool
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: tool.rawValue)
                        .font(.system(size: 18))

                    Text(tool.label)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private struct PropertyRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    private struct LayerRow: View {
        let icon: String
        let label: String
        let isVisible: Bool
        let isLocked: Bool

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(width: 16)

                Text(label)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
        }
    }

    private struct EffectRow: View {
        let label: String
        @Binding var value: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)

                Slider(value: $value, in: 0...100)
            }
        }
    }

    // MARK: - Formatted Values

    private var formattedDuration: String {
        let totalSeconds = Int(projectSummary.duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: projectSummary.updatedAt)
    }
}

// MARK: - Preview

#Preview {
    ProfessionalEditorView(
        projectSummary: ProjectSummary(
            projectId: UUID(),
            name: "Sample Project",
            createdAt: Date(),
            updatedAt: Date(),
            tags: ["demo", "tutorial"],
            duration: 83.5,
            thumbnailPath: nil
        )
    )
    .frame(width: 1200, height: 800)
}
