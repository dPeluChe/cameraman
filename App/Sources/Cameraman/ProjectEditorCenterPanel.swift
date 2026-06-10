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

    // Visibility toggles live on PreviewPlayerViewModel — binding local @State
    // here was the bug that made the old checkboxes do nothing.

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
            .frame(maxHeight: .infinity)

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
                .frame(height: 250)
            } else {
                 Color(NSColor.controlBackgroundColor)
                    .frame(height: 250)
            }

            // Preview visibility toggles (below timeline). Only switches that are
            // actually wired to the preview live here — Overlays/Layout/Captions
            // checkboxes were dead UI (local state, connected to nothing) and were
            // removed until those features gate the render for real.
            if viewModel.editor != nil {
                HStack(spacing: 14) {
                    Text("View:")
                        .foregroundStyle(.secondary)
                    Toggle("Zoom", isOn: $playerViewModel.showZoom)
                        .help("Apply the zoom plan during preview")
                    Divider().frame(height: 14)
                    Toggle("Cursor", isOn: $playerViewModel.showCursor)
                        .help("Show the recorded cursor position")
                    Toggle("Clicks", isOn: $playerViewModel.showClicks)
                        .help("Show recorded click markers")
                    Toggle("Keys", isOn: $playerViewModel.showKeystrokes)
                        .help("Show recorded keystrokes")
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
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
