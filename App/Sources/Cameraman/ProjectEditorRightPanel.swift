//
//  ProjectEditorRightPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//
//  Tools grid inspector: every tool is a tile (icon + title + usage badge).
//  Tapping a tile expands its controls full-width right below the tile's row;
//  tapping again collapses it. Tiles show a count badge (elements in use) or
//  an accent dot (feature active) so project state is visible at a glance.
//

import SwiftUI
import EngineKit

struct RightPanel: View {
    @ObservedObject var editor: ProjectEditor
    var selectedSegmentId: String?
    var selectedMediaItemId: UUID?
    var selectedOverlayId: Binding<UUID?> = .constant(nil)
    var playerViewModel: PreviewPlayerViewModel? = nil

    @Binding var showExportModal: Bool
    @Binding var showTranscriptionModal: Bool
    @Binding var showAISuggestionsModal: Bool

    @State private var selectedTool: EditorTool? = nil

    private let columns = 3
    private let gridSpacing: CGFloat = Spacing.sm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tools")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Divider()

                toolsGrid
                    .padding(Spacing.md)
            }
            .padding(.bottom, 40)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(width: 300)
        .onReceive(NotificationCenter.default.publisher(for: .selectEditorTool)) { notification in
            guard let raw = notification.object as? String,
                  let tool = EditorTool(rawValue: raw),
                  availableTools.contains(tool) else { return }
            selectedTool = tool
        }
        .onChangeCompat(of: availableToolIds) { _ in
            // A tool can disappear (e.g. camera removed from layout); don't
            // leave its detail expanded pointing at nothing.
            if let tool = selectedTool, !availableTools.contains(tool) {
                selectedTool = nil
            }
        }
    }

    // MARK: - Grid

    /// Tiles chunked into rows so the expanded detail can be inserted
    /// full-width directly below the row that owns the selected tile.
    private var toolsGrid: some View {
        let rows = availableTools.chunked(into: columns)
        return VStack(spacing: gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gridSpacing) {
                    ForEach(row) { tool in
                        ToolTile(
                            tool: tool,
                            status: status(for: tool),
                            isSelected: selectedTool == tool
                        ) {
                            selectedTool = (selectedTool == tool) ? nil : tool
                        }
                    }
                    // Pad the last row so tiles keep the same width.
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, minHeight: 0)
                        }
                    }
                }

                if let tool = selectedTool, row.contains(tool) {
                    expandedDetail(for: tool)
                }
            }
        }
        // Disable implicit expand/collapse animation: it caused the whole
        // right panel to jitter horizontally when adaptive grids reflowed.
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var availableTools: [EditorTool] {
        var tools: [EditorTool] = [.layout, .format]
        if editor.project.canvas.layout.camera != nil {
            tools.append(.camera)
        }
        tools += [.videoEffects, .background, .autoZoom]
        if playerViewModel != nil {
            tools.append(.manualZoom)
        }
        tools.append(.cursor)
        if !editor.project.mediaItems.isEmpty {
            tools.append(.mediaItems)
        }
        tools += [.overlays, .subtitles, .captionsAI, .export]
        return tools
    }

    private var availableToolIds: [String] {
        availableTools.map(\.id)
    }

    // MARK: - Status badges

    private func status(for tool: EditorTool) -> EditorToolStatus {
        let project = editor.project
        switch tool {
        case .layout, .format, .export:
            return .inactive
        case .camera:
            return EditorToolStatus(count: nil, isActive: true)
        case .videoEffects:
            let count = project.timeline.tracks
                .flatMap(\.clips)
                .reduce(0) { $0 + ($1.adjustments?.count ?? 0) }
            return EditorToolStatus(count: count, isActive: count > 0)
        case .background:
            let canvas = project.canvas
            // Default canvas is a plain solid fill with no padding/radius/shadow;
            // anything else means the user styled the background.
            let styled = canvas.background.type != "solid"
                || canvas.background.value != "#0B0B0D"
                || canvas.padding > 0
                || canvas.videoCornerRadius > 0
                || canvas.videoShadowIntensity > 0
            return EditorToolStatus(count: nil, isActive: styled)
        case .autoZoom:
            let count = project.timeline.segments.filter { $0.zoom?.enabled == true }.count
            return EditorToolStatus(count: count, isActive: count > 0)
        case .manualZoom:
            let count = project.manualZoomKeyframes?.count ?? 0
            return EditorToolStatus(count: count, isActive: count > 0)
        case .cursor:
            return EditorToolStatus(count: nil, isActive: project.syntheticCursor?.enabled == true)
        case .mediaItems:
            let count = project.mediaItems.count
            return EditorToolStatus(count: count, isActive: count > 0)
        case .overlays:
            let count = project.overlays.count
            return EditorToolStatus(count: count, isActive: count > 0)
        case .subtitles:
            let count = project.subtitles.count
            return EditorToolStatus(count: count, isActive: count > 0)
        case .captionsAI:
            return EditorToolStatus(count: nil, isActive: project.captions != nil)
        }
    }

    // MARK: - Expanded detail

    @ViewBuilder
    private func expandedDetail(for tool: EditorTool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tool.title, systemImage: tool.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    selectedTool = nil
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }
            .padding(.bottom, Spacing.sm)

            detailContent(for: tool)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .padding(Spacing.md)
        .background(AppColor.inset)
        .cornerRadius(Radius.medium)
    }

    @ViewBuilder
    private func detailContent(for tool: EditorTool) -> some View {
        switch tool {
        case .layout:
            LayoutSelectorView(editor: editor)
        case .format:
            FormatToggleView(editor: editor)
        case .camera:
            PiPConfigurationView(
                editor: editor,
                selectedSegmentId: selectedSegmentId,
                playerViewModel: playerViewModel
            )
        case .videoEffects:
            VideoEffectsControlsView(editor: editor)
        case .background:
            BackgroundControlsView(editor: editor)
        case .autoZoom:
            ZoomControlsView(editor: editor)
        case .manualZoom:
            if let pvm = playerViewModel {
                ManualZoomControlsView(editor: editor, playerViewModel: pvm)
            }
        case .cursor:
            SyntheticCursorControlsView(editor: editor)
        case .mediaItems:
            MediaItemInspectorView(
                editor: editor,
                selectedMediaItemId: selectedMediaItemId
            )
        case .overlays:
            OverlayEditorView(
                editor: editor,
                playheadTime: Binding(
                    get: { playerViewModel?.currentTime ?? 0 },
                    set: { _ in }
                ),
                selectedOverlayId: selectedOverlayId
            )
        case .subtitles:
            SubtitleEditorView(
                editor: editor,
                onSeek: { time in playerViewModel?.seek(to: time) }
            )
        case .captionsAI:
            VStack(spacing: Spacing.sm) {
                Button {
                    showTranscriptionModal = true
                } label: {
                    PanelActionLabel("Generate Captions...", icon: "captions.bubble")
                }
                .buttonStyle(.bordered)

                Button {
                    showAISuggestionsModal = true
                } label: {
                    PanelActionLabel("AI Assistant (MCP)...", icon: "sparkles")
                }
                .buttonStyle(.bordered)
                .help("Connect an AI assistant via MCP to edit this project")
            }
        case .export:
            Button {
                showExportModal = true
            } label: {
                PanelActionLabel("Export Video...", icon: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
