//
//  PreviewEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import os.log

/// Preview engine for playing back video with edits applied
/// Supports seek, play, pause, and applies trims/cuts/layouts from project
/// Also supports proxy generation for smooth preview of large files
public actor PreviewEngine {
    /// Structured logging
    let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "PreviewEngine")
    /// File manager for file operations
    let fileManager = FileManager.default
    /// The project being previewed
    var project: Project?

    /// Project directory path (for proxy generation)
    var projectDirectory: String?

    /// AVPlayer for video playback (exposed for AVPlayerLayer integration)
    public var player: AVPlayer?

    /// Current composition being played
    var composition: AVComposition?

    /// Video composition with transforms (PiP layout, scaling)
    var videoCompositionConfig: AVVideoComposition?

    /// Stored composition result for audio mix building
    var compositionResult: CompositionBuilder.Result?

    enum VideoTrackID: String, Hashable { case screen, camera }
    /// Which video tracks are currently muted (hidden) in preview
    var mutedVideoTracks: Set<VideoTrackID> = []

    /// Last applied audio mute state (preserved across rebuilds)
    var lastAudioMuteState: AudioMixBuilder.TrackMuteState = .init()

    /// Current playback state
    var playbackState: PlaybackState = .stopped

    /// Current playback time in seconds
    var currentTime: TimeInterval = 0

    /// Playback rate (1.0 = normal speed)
    var playbackRate: Double = 1.0

    /// Whether to loop playback
    var loopEnabled: Bool = false

    /// Configuration for preview
    var configuration: Configuration

    /// Proxy generator for creating low-resolution previews
    var proxyGenerator: ProxyGenerator

    /// Captions manager for displaying captions overlay
    var captionsManager: CaptionsManager

    /// Image overlay renderer for rendering imported images
    var imageOverlayRenderer: ImageOverlayRenderer?

    /// Zoom plan for auto-zoom rendering
    var zoomPlan: ZoomPlanGenerator.ZoomPlan?

    /// Set the zoom plan from external callers (e.g. suggestion engine).
    /// The plan is baked into freshly built composition instructions, so this
    /// rebuilds the videoComposition to apply the change immediately.
    public func setZoomPlan(_ plan: ZoomPlanGenerator.ZoomPlan?) async {
        self.zoomPlan = plan
        try? await rebuildVideoComposition()
    }

    /// Store the zoom plan without rebuilding the composition. Use this when
    /// the caller is about to trigger a rebuild itself (e.g. `updateProject`
    /// after a project mutation) so we don't pay for two rebuilds back-to-back.
    public func stageZoomPlan(_ plan: ZoomPlanGenerator.ZoomPlan?) {
        self.zoomPlan = plan
    }

    /// Whether zoom rendering is enabled
    var zoomEnabled: Bool = true

    /// Time observer token for periodic observation
    var timeObserverToken: Any?

    /// Configuration for preview
    public struct Configuration: Sendable {
        /// Whether to use low-quality proxy for smoother preview
        public let useProxy: Bool
        /// Proxy resolution (width)
        public let proxyWidth: Int
        /// Proxy resolution (height)
        public let proxyHeight: Int
        /// Whether to enable hardware acceleration
        public let hardwareAcceleration: Bool
        /// Whether to enable zoom rendering
        public let zoomEnabled: Bool

        public init(
            useProxy: Bool = true,
            proxyWidth: Int = 1280,
            proxyHeight: Int = 720,
            hardwareAcceleration: Bool = true,
            zoomEnabled: Bool = true
        ) {
            self.useProxy = useProxy
            self.proxyWidth = proxyWidth
            self.proxyHeight = proxyHeight
            self.hardwareAcceleration = hardwareAcceleration
            self.zoomEnabled = zoomEnabled
        }

        /// Default configuration for smooth preview
        public static let `default` = Configuration()

        /// High-quality configuration (no proxy)
        public static let highQuality = Configuration(useProxy: false)

        /// Configuration with zoom disabled
        public static let noZoom = Configuration(zoomEnabled: false)
    }

    /// Playback state
    public enum PlaybackState: Equatable, Sendable {
        case stopped
        case playing
        case paused
    }

    /// Preview error types
    public enum PreviewError: Error, Equatable, Sendable {
        case noProjectLoaded
        case projectLoadFailed(String)
        case playbackFailed(String)
        case seekFailed(String)
        case invalidTime(TimeInterval)
        case noSegments
        case mediaFileNotFound(String)

        public var localizedDescription: String {
            switch self {
            case .noProjectLoaded:
                return "No project loaded for preview"
            case .projectLoadFailed(let reason):
                return "Failed to load project: \(reason)"
            case .playbackFailed(let reason):
                return "Playback failed: \(reason)"
            case .seekFailed(let reason):
                return "Seek failed: \(reason)"
            case .invalidTime(let time):
                return "Invalid time: \(time)s"
            case .noSegments:
                return "Project has no segments to preview"
            case .mediaFileNotFound(let path):
                return "Media file not found: \(path)"
            }
        }
    }

    /// Preview session information
    public struct PreviewSession: Sendable {
        /// Current playback state
        public let state: PlaybackState
        /// Current playback time in seconds
        public let currentTime: TimeInterval
        /// Total duration in seconds
        public let duration: TimeInterval
        /// Playback rate
        public let playbackRate: Double
        /// Whether loop is enabled
        public let isLooping: Bool

        public init(
            state: PlaybackState,
            currentTime: TimeInterval,
            duration: TimeInterval,
            playbackRate: Double,
            isLooping: Bool
        ) {
            self.state = state
            self.currentTime = currentTime
            self.duration = duration
            self.playbackRate = playbackRate
            self.isLooping = isLooping
        }
    }

    // MARK: - Initialization

    /// Initialize with optional configuration
    /// - Parameter configuration: Preview configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.proxyGenerator = ProxyGenerator()
        self.captionsManager = CaptionsManager()
        self.zoomEnabled = configuration.zoomEnabled
    }

    /// Load a project for preview
    /// - Parameters:
    ///   - project: The project to preview
    ///   - projectDirectory: Optional project directory path (for proxy generation)
    /// - Throws: PreviewError if project cannot be loaded
    public func loadProject(_ project: Project, projectDirectory: String? = nil) async throws {
        // Clips on ANY track count — empty projects play imported overlay clips
        // without a recording (and without primarySources).
        guard project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) else {
            throw PreviewError.noSegments
        }

        self.project = project
        self.projectDirectory = projectDirectory

        // Initialize image overlay renderer
        if let projectDir = projectDirectory {
            self.imageOverlayRenderer = ImageOverlayRenderer(projectDirectory: URL(fileURLWithPath: projectDir))
        } else {
            self.imageOverlayRenderer = nil
        }
        self.currentTime = 0
        self.playbackState = .stopped

        // Load captions if available
        if let captions = project.captions, let projectDir = projectDirectory {
            await loadCaptions(srtPath: captions.srtPath, vttPath: captions.vttPath, projectDirectory: projectDir)
        } else {
            // Clear captions if none available
            await captionsManager.clear()
        }

        // Create AVPlayer with composition that applies edits
        try await createPlayerWithEdits()
    }

    /// Update the project and rebuild the composition (for live preview of edits)
    /// Call this when canvas layout, format, camera position, or timeline changes
    public func updateProject(_ project: Project) async throws {
        // PreviewPlayerView observes editor.objectWillChange and calls this on every
        // debounced tick — including for UI-only state that doesn't affect the composition.
        // Short-circuit when nothing actually changed to avoid cascading AVMutableVideoComposition rebuilds.
        if let existing = self.project, existing == project {
            return
        }

        let oldFormat = self.project?.canvas.format
        let oldClipCount = self.project?.timeline.primaryTrack?.clips.count
        // Overlay (.video/.audio) tracks live inside the AVComposition and the
        // cached compositionResult — any clip change there (import, move, trim,
        // PiP position) needs the full rebuild, not just a videoComposition pass.
        let oldOverlayTracks = self.project?.timeline.tracks.filter { $0.type != .primary }
        self.project = project

        let needsFullRebuild = oldFormat != project.canvas.format
            || oldClipCount != project.timeline.primaryTrack?.clips.count
            || oldOverlayTracks != project.timeline.tracks.filter { $0.type != .primary }

        if needsFullRebuild {
            // Full rebuild needed (different tracks or render size)
            let wasPlaying = playbackState == .playing
            let savedTime = currentTime

            player?.pause()
            try await createPlayerWithEdits()

            if savedTime > 0 {
                let cmTime = CMTime(seconds: savedTime, preferredTimescale: 600)
                await player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                currentTime = savedTime
            }

            if wasPlaying {
                player?.play()
                playbackState = .playing
            }
        } else {
            // Light update: only rebuild videoComposition (layout/camera/background)
            try await rebuildVideoComposition()
        }
    }

    /// Refresh overlays and visual effects without recreating the player
    public func refreshVisuals() async throws {
        try await rebuildVideoComposition()
    }

    /// Rebuild only the videoComposition without recreating tracks/player
    func rebuildVideoComposition() async throws {
        guard let project = project,
              let player = player,
              let currentItem = player.currentItem,
              let composition = self.composition as? AVMutableComposition else {
            return
        }

        let videoComposition = buildVideoComposition(
            for: project,
            composition: composition,
            staticClips: compositionResult?.staticClips ?? [],
            videoOverlays: compositionResult?.videoOverlaySources ?? []
        )
        self.videoCompositionConfig = videoComposition
        await MainActor.run {
            currentItem.videoComposition = videoComposition
            // Force a frame re-render when paused — AVFoundation won't call the compositor
            // for the current frame unless we seek after replacing the video composition.
            if player.timeControlStatus != .playing {
                player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        // Also rebuild audio mix to pick up per-segment volume changes
        if let compositionResult = compositionResult {
            let audioMix = AudioMixBuilder.buildAudioMix(
                compositionResult: compositionResult,
                muteState: lastAudioMuteState,
                segments: project.timeline.segments
            )
            nonisolated(unsafe) let unsafeAudioMix = audioMix
            await MainActor.run {
                currentItem.audioMix = unsafeAudioMix
            }
        }
    }

    /// Unload the current project
    public func unloadProject() {
        self.project = nil
        self.projectDirectory = nil
        stopPeriodicTimeObservation()
        self.player?.pause()
        self.player = nil
        self.currentTime = 0
        self.playbackState = .stopped

        // Clear captions
        Task {
            await captionsManager.clear()
        }

        // Clear zoom plan
        self.zoomPlan = nil
    }

}
