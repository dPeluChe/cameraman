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

    // Overlay visibility toggles
    @State private var showOverlays = true
    @State private var showLayout = true
    @State private var showZoom = true
    @State private var showCaptions = true
    @State private var showCursor = false
    @State private var showClicks = false
    @State private var showKeystrokes = false

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
                        viewModel: playerViewModel
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
                    mutedTracks: $viewModel.mutedTracks
                )
                .frame(height: 250)
            } else {
                 Color(NSColor.controlBackgroundColor)
                    .frame(height: 250)
            }

            // Visibility toggles (below timeline)
            if viewModel.editor != nil {
                HStack(spacing: 14) {
                    Toggle("Overlays", isOn: $showOverlays)
                    Toggle("Layout", isOn: $showLayout)
                    Toggle("Zoom", isOn: $showZoom)
                    Toggle("Captions", isOn: $showCaptions)
                    Divider().frame(height: 14)
                    Toggle("Cursor", isOn: $showCursor)
                    Toggle("Clicks", isOn: $showClicks)
                    Toggle("Keys", isOn: $showKeystrokes)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .focusable()
        .onKeyPress(.space) {
            NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            return .handled
        }
        .onChange(of: viewModel.mutedTracks) { _, newValue in
            playerViewModel.applyTrackMutes(mutedTracks: newValue)
        }
    }
}
