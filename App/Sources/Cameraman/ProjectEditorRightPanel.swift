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

/// Identity of each tool tile in the right panel. Raw values travel through
/// the `.selectEditorTool` notification (e.g. from the preview context menu).
enum EditorTool: String, CaseIterable, Identifiable {
    case layout
    case format
    case camera
    case videoEffects
    case background
    case autoZoom
    case manualZoom
    case cursor
    case mediaItems
    case overlays
    case subtitles
    case captionsAI
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: return "Layout"
        case .format: return "Format"
        case .camera: return "Camera"
        case .videoEffects: return "Effects"
        case .background: return "Background"
        case .autoZoom: return "Auto-Zoom"
        case .manualZoom: return "Manual Zoom"
        case .cursor: return "Cursor"
        case .mediaItems: return "Media"
        case .overlays: return "Overlays"
        case .subtitles: return "Subtitles"
        case .captionsAI: return "Captions & AI"
        case .export: return "Export"
        }
    }

    var icon: String {
        switch self {
        case .layout: return "rectangle.3.group"
        case .format: return "aspectratio"
        case .camera: return "camera"
        case .videoEffects: return "wand.and.stars"
        case .background: return "paintpalette"
        case .autoZoom: return "sparkle.magnifyingglass"
        case .manualZoom: return "plus.magnifyingglass"
        case .cursor: return "cursorarrow.motionlines"
        case .mediaItems: return "photo.on.rectangle.angled"
        case .overlays: return "pencil.and.outline"
        case .subtitles: return "captions.bubble"
        case .captionsAI: return "sparkles"
        case .export: return "square.and.arrow.up"
        }
    }
}

/// Per-tool usage summary shown on the tile: `count` renders a numeric badge,
/// `isActive` renders an accent dot (used when there's no natural count).
struct EditorToolStatus {
    var count: Int?
    var isActive: Bool

    static let inactive = EditorToolStatus(count: nil, isActive: false)
}

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
                    HStack {
                        Image(systemName: "captions.bubble")
                        Text("Generate Captions...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    showAISuggestionsModal = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("AI Assistant (MCP)...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .help("Connect an AI assistant via MCP to edit this project")
            }
        case .export:
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
        }
    }
}

// MARK: - Tool tile

private struct ToolTile: View {
    let tool: EditorTool
    let status: EditorToolStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: tool.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(height: 22)

                Text(tool.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : AppColor.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : AppColor.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                badge
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private var badge: some View {
        if let count = status.count, count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.accentColor))
        } else if status.isActive {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(2)
        }
    }

    private var helpText: String {
        if let count = status.count, count > 0 {
            return "\(tool.title) — \(count) in use"
        }
        return status.isActive ? "\(tool.title) — active" : tool.title
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
