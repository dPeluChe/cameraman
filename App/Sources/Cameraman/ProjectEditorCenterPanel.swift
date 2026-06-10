//
//  ProjectEditorCenterPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

struct CenterPanel: View {
    @ObservedObject var viewModel: ProjectEditorViewModel
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    @Binding var showExportModal: Bool
    @Binding var showTranscriptionModal: Bool

    /// Height that shows every timeline row without inner clipping: the window
    /// grows (or the user scrolls the window) instead of rows vanishing.
    private var timelineHeight: CGFloat {
        guard let editor = viewModel.editor else { return 250 }
        let rows = TimelineTrackBuilder.tracks(for: editor.project).reduce(0) { count, track in
            count + (track.kind == .overlay
                ? max(1, TimelineView.computeOverlayRows(overlays: track.overlays).count)
                : 1)
        }
        // toolbar + ruler + paddings ~= 120; row = 34 + 8 spacing
        return max(230, CGFloat(rows) * 42 + 120)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            ZStack {
                Color.black

                if let editor = viewModel.editor,
                   let projectDir = viewModel.projectDirectory {
                    PreviewPlayerView(
                        editor: editor,
                        projectDirectory: projectDir,
                        viewModel: playerViewModel,
                        selectedOverlayId: $viewModel.selectedOverlayId
                    )
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }
            .frame(minHeight: 240, maxHeight: .infinity)

            Divider()

            // Timeline
            if let editor = viewModel.editor {
                TimelineView(
                    editor: editor,
                    playerViewModel: playerViewModel,
                    projectDirectory: viewModel.projectDirectory,
                    mutedTracks: $viewModel.mutedTracks,
                    selectedSegmentId: $viewModel.selectedSegmentId,
                    selectedMediaItemId: $viewModel.selectedMediaItemId,
                    selectedOverlayId: $viewModel.selectedOverlayId
                )
                .frame(height: timelineHeight)
            } else {
                 Color(NSColor.controlBackgroundColor)
                    .frame(height: 250)
            }

        }
        .focusable()
        .spacePlaybackShortcut()
        .onChangeCompat(of: viewModel.mutedTracks) { newValue in
            playerViewModel.applyTrackMutes(mutedTracks: newValue)
        }
    }
}

private extension View {
    @ViewBuilder
    func spacePlaybackShortcut() -> some View {
        if #available(macOS 14.0, *) {
            self.onKeyPress(.space) {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
                return .handled
            }
        } else {
            self
        }
    }
}
