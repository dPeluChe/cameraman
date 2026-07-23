//
//  EditorToolTile.swift
//  App
//
//  Tool identity + tile view for the right panel tools grid. Split from
//  ProjectEditorRightPanel.swift to keep both files inside the size budget.
//

import SwiftUI

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

/// One tile of the tools grid: icon + title, usage badge top-trailing,
/// accent highlight while its detail is expanded.
struct ToolTile: View {
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
