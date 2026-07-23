//
//  PreviewPlayerView+ContextMenu.swift
//  App
//
//  Right-click menu on the preview: quick-add project properties at the
//  playhead, plus a Configure submenu that expands the matching tool in the
//  right panel (via the `.selectEditorTool` notification).
//

import EngineKit
import SwiftUI

extension PreviewPlayerView {
    @ViewBuilder
    var previewContextMenu: some View {
        Button {
            addOverlayAtPlayhead(type: .text)
        } label: {
            Label("Add Text Overlay", systemImage: "textformat")
        }

        Button {
            addOverlayAtPlayhead(type: .arrow)
        } label: {
            Label("Add Arrow Overlay", systemImage: "arrow.up.right")
        }

        Button {
            addOverlayAtPlayhead(type: .rect)
        } label: {
            Label("Add Rectangle Overlay", systemImage: "rectangle")
        }

        Button {
            addOverlayAtPlayhead(type: .line)
        } label: {
            Label("Add Line Overlay", systemImage: "line.diagonal")
        }

        Button {
            OverlayFactory.presentImagePicker { path in
                createImageOverlay(at: (0.5, 0.5), imagePath: path)
            }
        } label: {
            Label("Add Image Overlay...", systemImage: "photo")
        }

        Divider()

        Button {
            addZoomKeyframeAtPlayhead()
        } label: {
            Label("Add Zoom Keyframe at Playhead", systemImage: "plus.magnifyingglass")
        }

        Divider()

        Menu {
            ForEach(configurableTools) { tool in
                Button {
                    NotificationCenter.default.post(name: .selectEditorTool, object: tool.rawValue)
                } label: {
                    Label(tool.title, systemImage: tool.icon)
                }
            }
        } label: {
            Label("Configure", systemImage: "slider.horizontal.3")
        }
    }

    /// Tools offered in the "Configure" submenu — mirrors the availability
    /// rules of the right panel grid.
    private var configurableTools: [EditorTool] {
        EditorTool.allCases.filter { tool in
            switch tool {
            case .camera:
                return editor.project.canvas.layout.camera != nil
            case .mediaItems:
                return !editor.project.mediaItems.isEmpty
            default:
                return true
            }
        }
    }

    /// Create a shape/text overlay at the playhead with the shared factory
    /// defaults, then reveal the Overlays tool in the right panel.
    @MainActor
    private func addOverlayAtPlayhead(type: Project.Overlay.OverlayType) {
        let overlay = OverlayFactory.shapeOverlay(
            type: type,
            at: viewModel.currentTime,
            timelineDuration: editor.project.timeline.duration
        )
        Task {
            _ = await editor.addOverlay(projectId: editor.project.projectId, overlay: overlay)
            await MainActor.run {
                selectedOverlayId?.wrappedValue = overlay.id
                NotificationCenter.default.post(
                    name: .selectEditorTool,
                    object: EditorTool.overlays.rawValue
                )
            }
        }
    }

    @MainActor
    private func addZoomKeyframeAtPlayhead() {
        let time = viewModel.currentTime
        Task {
            _ = await editor.addManualZoomKeyframe(at: time, zoomLevel: 2.0)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .selectEditorTool,
                    object: EditorTool.manualZoom.rawValue
                )
            }
        }
    }
}
