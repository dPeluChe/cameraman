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
    @Published var playbackRate: PlaybackRate = .normal {
        didSet {
            guard isPlaying else { return }
            avPlayer?.rate = Float(playbackRate.rawValue)
        }
    }
    @Published var systemAudioVolume: Float = 1.0 {
        didSet { reapplyAudioMix() }
    }
    @Published var micAudioVolume: Float = 2.5 {
        didSet { reapplyAudioMix() }
    }
    @Published var showZoom: Bool = true {
        didSet {
            guard oldValue != showZoom else { return }
            applyEffectiveZoomPlan()
        }
    }
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

    /// Unfiltered plan as produced by the suggestion engine. The effective plan
    /// pushed to the compositor is this filtered by the current project's
    /// per-segment `zoom.enabled` state and gated by `showZoom`.
    private var originalZoomPlan: ZoomPlanGenerator.ZoomPlan?

    /// Store the unfiltered plan, then push the effective plan to the engine.
    /// Defers if the engine is still loading.
    func setZoomPlan(_ plan: ZoomPlanGenerator.ZoomPlan?) {
        originalZoomPlan = plan
        applyEffectiveZoomPlan()
    }

    /// Recompute the effective plan from the original plan, the current project's
    /// per-segment enabled state, and the global `showZoom` gate; push it to the
    /// engine, which bakes it into a fresh videoComposition.
    func applyEffectiveZoomPlan() {
        let effective = computeEffectiveZoomPlan()
        guard let engine = previewEngine else { return }
        Task { await engine.setZoomPlan(effective) }
    }

    /// Build the plan that should currently apply: nil when zoom is hidden, when
    /// no original plan exists, or when filtering wipes every event.
    func computeEffectiveZoomPlan() -> ZoomPlanGenerator.ZoomPlan? {
        guard showZoom, let plan = originalZoomPlan else { return nil }
        let segments = project?.timeline.segments ?? []
        let filtered = plan.filtered(byEnabledSegments: segments)
        return filtered.hasNoZoom ? nil : filtered
    }

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
        // Defer the entire body to a fresh Task so @Published mutations don't
        // happen during SwiftUI's view-update cycle. Caller is `.task(id:)`
        // which fires synchronously the first time the id resolves; running
        // our @Published assignments directly there triggers
        // "Publishing changes from within view updates is not allowed".
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            await self.performLoad(project: project, projectDirectory: projectDirectory)
        }
    }

    private func performLoad(project: Project?, projectDirectory: URL?) async {
        guard let project, let projectDirectory else {
            reset()
            return
        }

        self.project = project
        aspectRatio = Self.aspectRatio(for: project)
        updateDuration(project.timeline.duration)

        // Empty projects have no recording sources; the engine still builds a
        // composition from imported overlay clips, so only validate the screen
        // file when a recording exists.
        let screenSourcePath = project.primarySources.map {
            projectDirectory.appendingPathComponent($0.screen.path).path
        }

        guard screenSourcePath == nil || FileManager.default.fileExists(atPath: screenSourcePath!) else {
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

        do {
            try await engine.loadProject(project, projectDirectory: projectDirectory.path)
            let player = await engine.player

            // MainActor.run keeps these mutations out of any SwiftUI body cycle
            // the awaited continuation may have landed in.
            await MainActor.run {
                self.previewEngine = engine
                self.avPlayer = player
                self.loadError = nil
                self.currentTime = 0
                self.setupPlayerObservers()
                self.applyEffectiveZoomPlan()
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

    /// Push an overlay-transform draft directly to the engine, bypassing
    /// `editor.project` publication + the 150ms debounce in PreviewPlayerView.
    /// Used by OverlayInteractionLayer during an active drag. Official
    /// editor.updateOverlay still fires on gesture end.
    func previewOverlayDraft(_ transform: Project.Overlay.Transform, overlayId: UUID) {
        guard let baseProject = project, let engine = previewEngine else { return }
        var temp = baseProject
        guard let idx = temp.overlays.firstIndex(where: { $0.id == overlayId }) else { return }
        temp.overlays[idx].transform = transform
        Task { try? await engine.updateProject(temp) }
    }

    /// Push a camera-position-only draft directly to the engine, bypassing
    /// `editor.project` publication + the 150ms debounce in PreviewPlayerView.
    /// Used by PiPCanvasEditor during an active drag so the live AVPlayer
    /// reflects the in-progress position. The official editor.project update
    /// happens on gesture release (via the existing commitCamera path); this
    /// just keeps the visual in sync mid-drag.
    /// Hits `PreviewEngine.updateProject` light path (camera position alone
    /// doesn't change render size or clip count) → `currentItem.videoComposition`
    /// is swapped in-place, no AVPlayer recreation, no playback reset.
    func previewCameraDraft(_ camera: Project.Canvas.Layout.CameraPosition, segmentId: String?) {
        guard let baseProject = project, let engine = previewEngine else { return }
        var temp = baseProject
        if let segId = segmentId,
           let idx = temp.timeline.segments.firstIndex(where: { $0.id == segId }) {
            temp.timeline.segments[idx].cameraPosition = camera
        } else {
            temp.canvas.layout.camera = camera
        }
        Task { try? await engine.updateProject(temp) }
    }

    /// Rebuild the preview composition when project settings change
    func refreshPreview(with project: Project) {
        guard let engine = previewEngine else { return }

        self.project = project
        aspectRatio = Self.aspectRatio(for: project)
        updateDuration(project.timeline.duration)

        // Set the engine's zoom plan BEFORE updateProject so the rebuild
        // bakes in the effective plan in a single pass (instead of rebuilding,
        // then rebuilding again to apply the new plan).
        let effectivePlan = computeEffectiveZoomPlan()

        Task {
            do {
                await engine.stageZoomPlan(effectivePlan)
                try await engine.updateProject(project)
                let player = await engine.player

                // MainActor.run NOT redundant — see comment in load(...).
                await MainActor.run {
                    if self.avPlayer !== player {
                        self.removePlayerObservers()
                        self.avPlayer = player
                        self.setupPlayerObservers()
                    }
                }
            } catch {
                LogError(.preview, "Failed to refresh preview: \(error.localizedDescription)")
            }
        }
    }

    /// Fast overlay-only refresh (rebuilds videoComposition without full engine reload)
    func refreshOverlayPreview() async {
        guard let engine = previewEngine else { return }

        do {
            try await engine.refreshVisuals()
        } catch {
            LogError(.preview, "Failed to refresh overlay preview: \(error.localizedDescription)")
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
        systemAudioVolume = 1.0
        micAudioVolume = 2.5
        project = nil
        // Clear the zoom plan first so the showZoom didSet (below) can't push
        // a stale plan to the compositor on its way back to true.
        originalZoomPlan = nil
        showZoom = true
        showCursor = false
        showClicks = false
        showKeystrokes = false
        lastMuteState = nil
    }

    func togglePlayPause() {
        guard let player = avPlayer else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If at end of video, restart from beginning
            if duration > 0 && currentTime >= duration - 0.1 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentTime = 0
            }
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
            Task { @MainActor [weak self] in
                guard let self = self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }

        // End-of-playback observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
            }
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

    // MARK: - Audio Mix

    private var lastMuteState: AudioMixBuilder.TrackMuteState?

    func applyTrackMutes(mutedTracks: Set<TimelineTrackKind>) {
        guard let engine = previewEngine else { return }

        let audioMuteState = AudioMixBuilder.TrackMuteState(
            systemAudioMuted: mutedTracks.contains(.systemAudio),
            micAudioMuted: mutedTracks.contains(.micAudio),
            systemAudioVolume: systemAudioVolume,
            micAudioVolume: micAudioVolume
        )
        let audioChanged = audioMuteState != lastMuteState
        if audioChanged { lastMuteState = audioMuteState }

        let screenMuted = mutedTracks.contains(.screen)
        let cameraMuted = mutedTracks.contains(.camera)

        Task {
            if audioChanged {
                await engine.applyAudioMix(audioMuteState)
            }
            await engine.applyVideoMutes(screenMuted: screenMuted, cameraMuted: cameraMuted)
        }
    }

    private func reapplyAudioMix() {
        guard let engine = previewEngine else { return }
        let audioMuteState = AudioMixBuilder.TrackMuteState(
            systemAudioMuted: lastMuteState?.systemAudioMuted ?? false,
            micAudioMuted: lastMuteState?.micAudioMuted ?? false,
            systemAudioVolume: systemAudioVolume,
            micAudioVolume: micAudioVolume
        )
        guard audioMuteState != lastMuteState else { return }
        lastMuteState = audioMuteState
        Task { await engine.applyAudioMix(audioMuteState) }
    }

    nonisolated deinit {
        // Note: can't access MainActor properties in deinit
        // Observers are cleaned up in reset() / removePlayerObservers()
    }
}
