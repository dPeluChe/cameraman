//
//  PreviewPlayerView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import AVFoundation
import AVKit
import CoreGraphics
import EngineKit
import SwiftUI

@MainActor
final class PreviewPlayerViewModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var aspectRatio: Double = PreviewPlayerViewModel.fallbackAspectRatio
    @Published private(set) var loadError: String?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isScrubbing: Bool = false

    private static let fallbackAspectRatio: Double = 16.0 / 9.0
    private var timeObserverToken: Any?
    private var timeControlObserver: NSKeyValueObservation?

    func load(project: Project?, projectDirectory: URL?) {
        guard let project, let projectDirectory else {
            reset()
            return
        }

        aspectRatio = Self.aspectRatio(for: project)
        updateDuration(project.timeline.duration)
        let sourceURL = projectDirectory.appendingPathComponent(project.sources.screen.path)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            detachPlayer()
            player = nil
            loadError = "Preview source missing."
            currentTime = 0
            isPlaying = false
            return
        }

        let previewPlayer = AVPlayer(url: sourceURL)
        previewPlayer.actionAtItemEnd = .pause
        previewPlayer.pause()
        attachPlayer(previewPlayer)
        loadError = nil
    }

    func reset() {
        detachPlayer()
        player = nil
        aspectRatio = Self.fallbackAspectRatio
        loadError = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isScrubbing = false
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func stopPlayback() {
        guard let player else {
            currentTime = 0
            isPlaying = false
            return
        }
        player.pause()
        player.seek(to: .zero)
        currentTime = 0
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let clamped = clampTime(seconds)
        currentTime = clamped
        guard let player else { return }
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration)
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    func updateDuration(_ newDuration: Double) {
        let clamped = max(0, newDuration)
        duration = clamped
        if currentTime > clamped {
            currentTime = clamped
        }
    }

    static func aspectRatio(for project: Project) -> Double {
        // Use project canvas format aspect ratio instead of source dimensions
        // This allows preview to reflect 16:9 vs 9:16 format selection
        let width = Double(project.canvas.format.w)
        let height = Double(project.canvas.format.h)
        guard width > 0, height > 0 else {
            return fallbackAspectRatio
        }
        return width / height
    }

    private func attachPlayer(_ player: AVPlayer) {
        detachPlayer()
        self.player = player
        timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.isPlaying = player.timeControlStatus == .playing
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                if let item = player.currentItem {
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite, itemDuration > 0 {
                        self.updateDuration(itemDuration)
                    }
                }
                guard !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
    }

    private func detachPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        timeControlObserver = nil
    }

    private func clampTime(_ seconds: Double) -> Double {
        guard duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }
}

struct PreviewPlayerView: View {
    let project: Project?
    let projectDirectory: URL?

    @StateObject private var viewModel = PreviewPlayerViewModel()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.9))

                if let player = viewModel.player {
                    PreviewPlayerContainer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text(viewModel.loadError ?? "Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(CoreGraphics.CGFloat(viewModel.aspectRatio), contentMode: .fit)
            .frame(maxWidth: .infinity)

            PlaybackControlsView(viewModel: viewModel)
        }
        .task(id: project?.projectId) {
            viewModel.load(project: project, projectDirectory: projectDirectory)
        }
    }
}

private struct PreviewPlayerContainer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.updatesNowPlayingInfoCenter = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
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
            .disabled(viewModel.player == nil)

            Button(action: viewModel.stopPlayback) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.player == nil)

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
            .disabled(viewModel.player == nil || viewModel.duration == 0)

            Text("\(viewModel.formattedCurrentTime) / \(viewModel.formattedDuration)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }
}
