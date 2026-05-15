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
import UniformTypeIdentifiers

extension Notification.Name {
    static let togglePlayPause = Notification.Name("togglePlayPause")
}

struct PreviewPlayerView: View {
    @ObservedObject var editor: ProjectEditor
    let projectDirectory: URL?
    @ObservedObject var viewModel: PreviewPlayerViewModel
    var selectedOverlayId: Binding<UUID?>? = nil

    private var project: Project? { editor.project }

    var body: some View {
        VStack(spacing: 8) {
            // Video preview area
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.9))

                if let avPlayer = viewModel.avPlayer {
                    GeometryReader { geo in
                        AVPlayerLayerView(player: avPlayer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers, location in
                                handleImageDrop(providers: providers, dropLocation: location, previewSize: geo.size)
                            }
                    }

                    if let selectedOverlayId {
                        OverlayInteractionLayer(
                            editor: editor,
                            playerViewModel: viewModel,
                            selectedOverlayId: selectedOverlayId
                        )
                    }

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

            // Playback controls
            PlaybackControlsView(viewModel: viewModel)
        }
        .task(id: editor.project.projectId) {
            viewModel.load(project: editor.project, projectDirectory: projectDirectory)
        }
        // Listen to changes in the Project specifically (with dedup) instead of
        // editor.objectWillChange. The editor also publishes transient UI state
        // (showAutosaveToast, canUndo, canRedo) which don't affect the preview
        // — listening to those triggered up to 2 spurious composition rebuilds
        // per autosave plus one per undo/redo state flip.
        .onReceive(
            editor.$project
                .removeDuplicates()
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        ) { [weak viewModel] project in
            guard let viewModel = viewModel,
                  viewModel.previewEngine != nil,
                  viewModel.project?.projectId == project.projectId else { return }
            viewModel.refreshPreview(with: project)
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            viewModel.togglePlayPause()
        }
    }

    /// Handle a file drop onto the preview area. Accepts PNG/JPG/SVG/GIF and
    /// creates an `.image` overlay positioned at the drop location, anchored
    /// at the current playhead with a 2s default window and fadeInOut animation.
    private func handleImageDrop(providers: [NSItemProvider], dropLocation: CGPoint, previewSize: CGSize) -> Bool {
        let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "svg", "gif", "heic"]
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            // The item may arrive as Data (security-scoped URL bookmark) or NSURL.
            var url: URL?
            if let data = item as? Data, let pathURL = URL(dataRepresentation: data, relativeTo: nil) {
                url = pathURL
            } else if let nsurl = item as? URL {
                url = nsurl
            }
            guard let fileURL = url else { return }
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return }

            // Normalize coordinates: drop location in SwiftUI space → renderer
            // Y-flipped convention used by the rest of the overlay system.
            let normX = max(0, min(1, Double(dropLocation.x / previewSize.width)))
            let normYTopLeft = max(0, min(1, Double(dropLocation.y / previewSize.height)))
            let normY = 1.0 - normYTopLeft

            Task { @MainActor in
                createImageOverlay(at: (normX, normY), imagePath: fileURL.path)
            }
        }
        return true
    }

    @MainActor
    private func createImageOverlay(at position: (x: Double, y: Double), imagePath: String) {
        let start = viewModel.currentTime
        let remaining = editor.project.timeline.duration - start
        let duration = max(0.5, min(2.0, remaining))
        let end = start + duration
        let fadeDuration = min(0.3, duration / 4)

        let overlay = Project.Overlay(
            id: UUID(),
            type: .image,
            start: start,
            end: end,
            transform: Project.Overlay.Transform(x: position.x, y: position.y, scale: 1.0),
            style: Project.Overlay.Style(
                stroke: "#FFFFFF",
                strokeWidth: 0,
                shadow: false,
                imagePath: imagePath,
                imageOpacity: 1.0
            ),
            animation: Project.Overlay.Animation(
                type: .fadeInOut,
                fadeInDuration: fadeDuration,
                fadeOutDuration: fadeDuration
            )
        )

        Task {
            _ = await editor.addOverlay(projectId: editor.project.projectId, overlay: overlay)
            await MainActor.run { selectedOverlayId?.wrappedValue = overlay.id }
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
