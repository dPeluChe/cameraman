//
//  PreviewPlayerViewModel.swift
//  App
//
//  View model for preview player — uses native AVPlayer for fluid playback
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
    @Published private(set) var avPlayer: AVPlayer?
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
    @Published var isMuted: Bool = false {
        didSet { avPlayer?.isMuted = isMuted }
    }

    private static let fallbackAspectRatio: Double = 16.0 / 9.0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
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

        guard project.primarySources != nil else {
            reset()
            return
        }

        let sourcePath = projectDirectory.appendingPathComponent(project.primarySources!.screen.path).path

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            previewEngine = nil
            avPlayer = nil
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

                // Get the AVPlayer from the engine
                let player = await engine.player

                await MainActor.run {
                    self.previewEngine = engine
                    self.avPlayer = player
                    self.loadError = nil
                    self.currentTime = 0
                    self.setupPlayerObservers()
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.previewEngine = nil
                    self.avPlayer = nil
                    self.currentFrame = nil
                }
            }
        }
    }

    func reset() {
        removePlayerObservers()
        avPlayer?.pause()
        previewEngine = nil
        avPlayer = nil
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

    func togglePlayPause() {
        guard let player = avPlayer else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = Float(playbackRate.rawValue)
            isPlaying = true
        }
    }

    func stopPlayback() {
        guard let player = avPlayer else {
            currentTime = 0
            isPlaying = false
            return
        }

        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = 0
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let clamped = clampTime(seconds)
        currentTime = clamped

        guard let player = avPlayer else { return }

        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if scrubbing {
            avPlayer?.pause()
        } else if isPlaying {
            avPlayer?.rate = Float(playbackRate.rawValue)
        }
    }

    // MARK: - Player Observers

    private func setupPlayerObservers() {
        guard let player = avPlayer else { return }

        // Periodic time observer for scrubber updates
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isScrubbing else { return }
            self.currentTime = time.seconds
        }

        // End-of-playback observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.currentTime = self?.duration ?? 0
        }
    }

    private func removePlayerObservers() {
        if let observer = timeObserver, let player = avPlayer {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil

        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
    }

    // MARK: - Helpers

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration)
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
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
        guard width > 0, height > 0 else { return fallbackAspectRatio }
        return width / height
    }

    private func clampTime(_ seconds: Double) -> Double {
        guard duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    nonisolated deinit {
        // Note: can't access MainActor properties in deinit
        // Observers are cleaned up in reset() / removePlayerObservers()
    }
}
