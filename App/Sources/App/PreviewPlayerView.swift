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

@MainActor
final class PreviewPlayerViewModel: ObservableObject {
    @Published private(set) var previewEngine: PreviewEngine?
    @Published private(set) var aspectRatio: Double = PreviewPlayerViewModel.fallbackAspectRatio
    @Published private(set) var loadError: String?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isScrubbing: Bool = false
    @Published private(set) var currentFrame: CGImage?
    @Published var playbackRate: PlaybackRate = .normal
    @Published var showOverlays: Bool = true
    @Published var showLayout: Bool = true
    @Published var showZoom: Bool = true
    @Published var showCaptions: Bool = true
    @Published var showCursor: Bool = false
    @Published var showClicks: Bool = false
    @Published var showKeystrokes: Bool = false
    @Published private(set) var project: Project?

    private static let fallbackAspectRatio: Double = 16.0 / 9.0
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    enum PlaybackRate: Double, CaseIterable, Identifiable {
        case half = 0.5
        case normal = 1.0
        case double = 2.0

        var id: Double { rawValue }

        var displayName: String {
            switch self {
            case .half: return "0.5x"
            case .normal: return "1x"
            case .double: return "2x"
            }
        }
    }

    func load(project: Project?, projectDirectory: URL?) {
        guard let project, let projectDirectory else {
            reset()
            return
        }

        self.project = project
        aspectRatio = Self.aspectRatio(for: project)
        updateDuration(project.timeline.duration)
        let sourcePath = projectDirectory.appendingPathComponent(project.sources.screen.path).path

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            stopUpdateTimer()
            previewEngine = nil
            currentFrame = nil
            loadError = "Preview source missing."
            currentTime = 0
            isPlaying = false
            return
        }

        // Create PreviewEngine with edits enabled
        let engine = PreviewEngine(
            configuration: PreviewEngine.Configuration(
                useProxy: false, // Use full quality for preview
                hardwareAcceleration: true,
                zoomEnabled: showZoom
            )
        )

        Task {
            do {
                try await engine.loadProject(project, projectDirectory: sourcePath)
                await MainActor.run {
                    self.previewEngine = engine
                    self.loadError = nil
                    self.currentTime = 0
                    self.updateCurrentFrame()
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.previewEngine = nil
                    self.currentFrame = nil
                }
            }
        }
    }

    func reset() {
        stopUpdateTimer()
        previewEngine = nil
        currentFrame = nil
        aspectRatio = Self.fallbackAspectRatio
        loadError = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isScrubbing = false
        playbackRate = .normal
        project = nil
        showCursor = false
        showClicks = false
        showKeystrokes = false
    }

    func setPlaybackRate(_ rate: PlaybackRate) {
        playbackRate = rate
        guard let engine = previewEngine else { return }
        Task {
            try? await engine.setPlaybackRate(rate.rawValue)
        }
    }

    func togglePlayPause() {
        guard let engine = previewEngine else { return }

        Task {
            if isPlaying {
                try? await engine.pause()
                await MainActor.run {
                    self.isPlaying = false
                    self.stopUpdateTimer()
                }
            } else {
                try? await engine.play()
                await MainActor.run {
                    self.isPlaying = true
                    self.startUpdateTimer()
                }
            }
        }
    }

    func stopPlayback() {
        guard let engine = previewEngine else {
            currentTime = 0
            isPlaying = false
            return
        }

        Task {
            try? await engine.stop()
            await MainActor.run {
                self.currentTime = 0
                self.isPlaying = false
                self.stopUpdateTimer()
                self.updateCurrentFrame()
            }
        }
    }

    func seek(to seconds: Double) {
        let clamped = clampTime(seconds)
        currentTime = clamped

        guard let engine = previewEngine else { return }

        Task {
            try? await engine.seek(to: clamped)
            await MainActor.run {
                self.updateCurrentFrame()
            }
        }
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing {
            updateCurrentFrame()
        }
    }

    private func updateCurrentFrame() {
        guard let engine = previewEngine, !isScrubbing else { return }

        Task {
            do {
                let frame = try await engine.extractFrame(at: currentTime)
                await MainActor.run {
                    self.currentFrame = frame
                }
            } catch {
                // Silently fail frame extraction during playback
                // (frame extraction may fail during rapid updates)
            }
        }
    }

    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }

            Task {
                if let engine = await self.previewEngine {
                    let session = await engine.getSession()
                    await MainActor.run {
                        self.currentTime = session.currentTime
                        self.updateDuration(session.duration)
                    }

                    // Update frame at 15fps for smoother performance
                    if Int(session.currentTime * 15) % 1 == 0 {
                        self.updateCurrentFrame()
                    }

                    // Handle playback end
                    if session.currentTime >= session.duration && session.duration > 0 {
                        self.stopPlayback()
                    }
                }
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
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

    private func clampTime(_ seconds: Double) -> Double {
        guard duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    deinit {
        stopUpdateTimer()
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

                if let frame = viewModel.currentFrame {
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Telemetry overlay
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
        .task(id: project?.projectId) {
            viewModel.load(project: project, projectDirectory: projectDirectory)
        }
        .onDisappear {
            viewModel.stopPlayback()
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
