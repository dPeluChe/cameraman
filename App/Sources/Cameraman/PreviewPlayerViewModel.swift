//
//  PreviewPlayerViewModel.swift
//  App
//
//  Extracted from PreviewPlayerView.swift
//  View model for preview player
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

        guard let sources = project.primarySources else {
            reset()
            return
        }

        let sourcePath = projectDirectory.appendingPathComponent(sources.screen.path).path

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            stopUpdateTimer()
            previewEngine = nil
            currentFrame = nil
            loadError = "Preview source missing."
            currentTime = 0
            isPlaying = false
            return
        }

        let engine = PreviewEngine(
            configuration: PreviewEngine.Configuration(
                useProxy: false,
                hardwareAcceleration: true,
                zoomEnabled: showZoom
            )
        )

        Task {
            do {
                try await engine.loadProject(project, projectDirectory: projectDirectory.path)
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
        guard let engine = previewEngine else {
            print("[PLAYER-DEBUG] togglePlayPause: no engine")
            return
        }

        print("[PLAYER-DEBUG] togglePlayPause: isPlaying=\(isPlaying)")
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

        guard let engine = previewEngine else {
            print("[PLAYER-DEBUG] seek: no engine")
            return
        }

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
            }
        }
    }

    private func startUpdateTimer() {
        stopUpdateTimer()

        self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }

                if let engine = self.previewEngine {
                    let session = await engine.getSession()
                    self.currentTime = session.currentTime
                    self.updateDuration(session.duration)

                    if Int(session.currentTime * 15) % 1 == 0 {
                        self.updateCurrentFrame()
                    }

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
}
