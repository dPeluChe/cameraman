//
//  PreviewPlayerView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import AVFoundation
import AVKit
import CoreGraphics
import CoreImage
import EngineKit
import SwiftUI
import Combine

struct PreviewPlayerView: View {
    @ObservedObject var editor: ProjectEditor
    let projectDirectory: URL?

    @StateObject private var viewModel = PreviewPlayerViewModel()

    private var project: Project? { editor.project }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.9))

                // Native AVPlayerLayer for fluid playback
                if let avPlayer = viewModel.avPlayer {
                    AVPlayerLayerView(player: avPlayer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Telemetry overlay on top of the player
                    if viewModel.showCursor || viewModel.showClicks || viewModel.showKeystrokes {
                        GeometryReader { geometry in
                            TelemetryOverlayView(
                                project: viewModel.project,
                                projectDirectory: projectDirectory,
                                currentTime: viewModel.currentTime,
                                showCursor: viewModel.showCursor,
                                showClicks: viewModel.showClicks,
                                showKeystrokes: viewModel.showKeystrokes,
                                overlaySize: geometry.size
                            )
                        }
                    }
                } else if viewModel.previewEngine != nil {
                    ProgressView("Loading preview...")
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.loadError ?? "Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(CoreGraphics.CGFloat(viewModel.aspectRatio), contentMode: .fit)
            .frame(maxWidth: .infinity)

            // Edit visibility toggles
            if viewModel.previewEngine != nil {
                HStack(spacing: 16) {
                    Toggle("Overlays", isOn: $viewModel.showOverlays)
                        .toggleStyle(.checkbox)
                    Toggle("Layout", isOn: $viewModel.showLayout)
                        .toggleStyle(.checkbox)
                    Toggle("Zoom", isOn: $viewModel.showZoom)
                        .toggleStyle(.checkbox)
                    Toggle("Captions", isOn: $viewModel.showCaptions)
                        .toggleStyle(.checkbox)
                    Toggle("Cursor", isOn: $viewModel.showCursor)
                        .toggleStyle(.checkbox)
                    Toggle("Clicks", isOn: $viewModel.showClicks)
                        .toggleStyle(.checkbox)
                    Toggle("Keys", isOn: $viewModel.showKeystrokes)
                        .toggleStyle(.checkbox)
                }
                .font(.caption)
                .padding(.horizontal, 8)
            }

            PlaybackControlsView(viewModel: viewModel)
        }
        .task(id: editor.project.projectId) {
            viewModel.load(project: editor.project, projectDirectory: projectDirectory)
        }
        .onReceive(editor.objectWillChange.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { [weak viewModel] _ in
            guard let viewModel = viewModel,
                  viewModel.previewEngine != nil,
                  viewModel.project?.projectId == editor.project.projectId else { return }
            viewModel.refreshPreview(with: editor.project)
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
        .focusable()
        .onKeyPress(.space) {
            viewModel.togglePlayPause()
            return .handled
        }
    }
}

private struct PlaybackControlsView: View {
    @ObservedObject var viewModel: PreviewPlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.previewEngine == nil)

            Button(action: viewModel.stopPlayback) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.previewEngine == nil)

            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 0.01),
                onEditingChanged: { isEditing in
                    viewModel.setScrubbing(isEditing)
                }
            )
            .disabled(viewModel.previewEngine == nil || viewModel.duration == 0)

            Text("\(viewModel.formattedCurrentTime) / \(viewModel.formattedDuration)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 88, alignment: .trailing)

            Picker("", selection: $viewModel.playbackRate) {
                ForEach(PreviewPlayerViewModel.PlaybackRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(viewModel.previewEngine == nil)
        }
        .padding(.horizontal, 8)
    }
}
