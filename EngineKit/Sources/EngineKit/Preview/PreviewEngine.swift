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

    /// Zoom plan for auto-zoom rendering
    var zoomPlan: ZoomPlanGenerator.ZoomPlan?

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
        guard !project.timeline.segments.isEmpty else {
            throw PreviewError.noSegments
        }
        
        guard let sources = project.primarySources else {
            throw PreviewError.playbackFailed("No sources found in project")
        }

        // Verify screen media file exists
        // In a real implementation, we would check file existence here
        // For testing, we'll just store the project
        _ = sources.screen.path

        self.project = project
        self.projectDirectory = projectDirectory
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
        let oldFormat = self.project?.canvas.format
        let oldSegmentCount = self.project?.timeline.segments.count

        self.project = project

        let formatChanged = oldFormat != project.canvas.format
        let segmentsChanged = oldSegmentCount != project.timeline.segments.count

        if formatChanged || segmentsChanged {
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

    /// Rebuild only the videoComposition without recreating tracks/player
    /// Used for fast PiP position, camera size, and background changes
    private func rebuildVideoComposition() async throws {
        guard let project = project,
              let player = player,
              let currentItem = player.currentItem,
              let composition = self.composition as? AVMutableComposition else {
            return
        }

        let videoComposition = buildVideoComposition(for: project, composition: composition)
        self.videoCompositionConfig = videoComposition

        currentItem.videoComposition = videoComposition
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

    // MARK: - Playback Control

    /// Start playback from current position
    /// - Throws: PreviewError if playback cannot start
    public func play() async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard !project.timeline.segments.isEmpty else {
            throw PreviewError.noSegments
        }

        player?.play()
        playbackState = .playing
        playbackRate = 1.0

        // Start time observer for current time tracking
        startPeriodicTimeObservation()
    }

    /// Pause playback
    /// - Throws: PreviewError if playback cannot be paused
    public func pause() async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        player?.pause()
        playbackState = .paused
        stopPeriodicTimeObservation()
    }

    /// Stop playback and reset to beginning
    /// - Throws: PreviewError if playback cannot be stopped
    public func stop() async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        player?.pause()
        await player?.seek(to: .zero)
        currentTime = 0
        playbackState = .stopped
        stopPeriodicTimeObservation()
    }

    /// Seek to a specific time in the preview
    /// - Parameter time: Time in seconds to seek to
    /// - Throws: PreviewError if seek fails
    public func seek(to time: TimeInterval) async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard time >= 0 && time <= project.timeline.duration else {
            throw PreviewError.invalidTime(time)
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    /// Set playback rate (speed)
    /// - Parameter rate: Playback rate (1.0 = normal, 2.0 = 2x speed, 0.5 = half speed)
    /// - Throws: PreviewError if rate cannot be set
    public func setPlaybackRate(_ rate: Double) async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        guard rate > 0 && rate <= 4.0 else {
            throw PreviewError.playbackFailed("Invalid playback rate: \(rate)")
        }

        player?.rate = Float(rate * (playbackState == .playing ? 1.0 : 0.0))
        playbackRate = rate
    }

    /// Enable or disable looping
    /// - Parameter enabled: Whether to enable looping
    public func setLooping(_ enabled: Bool) {
        loopEnabled = enabled
    }

    // MARK: - Time Observation

    /// Update current time from observer (actor-isolated)
    private func updateCurrentTime(_ time: TimeInterval) {
        self.currentTime = time
    }

    /// Start periodic time observation for tracking current time
    private func startPeriodicTimeObservation() {
        guard let player = player else { return }

        // Remove any existing observer
        stopPeriodicTimeObservation()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task {
                await self.updateCurrentTime(time.seconds)
            }
        }
    }

    /// Stop periodic time observation
    private func stopPeriodicTimeObservation() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    // MARK: - State Query

    /// Get current preview session information
    /// - Returns: PreviewSession with current state
    public func getSession() -> PreviewSession {
        let duration = project?.timeline.duration ?? 0
        return PreviewSession(
            state: playbackState,
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            isLooping: loopEnabled
        )
    }

    /// Get current playback time
    /// - Returns: Current time in seconds
    public func getCurrentTime() -> TimeInterval {
        return currentTime
    }

    /// Get total duration
    /// - Returns: Total duration in seconds
    public func getDuration() -> TimeInterval {
        return project?.timeline.duration ?? 0
    }

    /// Get playback state
    /// - Returns: Current playback state
    public func getPlaybackState() -> PlaybackState {
        return playbackState
    }

    /// Check if currently playing
    /// - Returns: True if playing
    public func isPlaying() -> Bool {
        return playbackState == .playing
    }

    /// Check if currently paused
    /// - Returns: True if paused
    public func isPaused() -> Bool {
        return playbackState == .paused
    }

    /// Check if currently stopped
    /// - Returns: True if stopped
    public func isStopped() -> Bool {
        return playbackState == .stopped
    }


    // MARK: - Proxy Generation

    /// Generate proxies for the current project
    /// - Parameters:
    ///   - projectDirectory: Project's directory path
    ///   - configuration: Optional proxy configuration (uses default if nil)
    ///   - progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: Dictionary of track type to ProxyResult
    /// - Throws: PreviewError if generation fails
    public func generateProxies(
        projectDirectory: String,
        configuration: ProxyGenerator.Configuration? = nil,
        progress: ProxyGenerator.ProgressHandler? = nil
    ) async throws -> [String: ProxyGenerator.ProxyResult] {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        let proxyConfig = configuration ?? ProxyGenerator.Configuration(
            width: self.configuration.proxyWidth,
            height: self.configuration.proxyHeight
        )

        return try await proxyGenerator.generateProjectProxies(
            for: project,
            projectDirectory: projectDirectory,
            configuration: proxyConfig,
            progress: progress
        )
    }

    /// Check if proxies are available for the current project
    /// - Returns: True if proxies exist and should be used
    public func hasProxies() -> Bool {
        guard project != nil,
              let projectDir = projectDirectory else {
            return false
        }

        // Check if screen proxy exists
        let screenProxyPath = (projectDir as NSString).appendingPathComponent("proxies/screen_proxy.mov")
        return FileManager.default.fileExists(atPath: screenProxyPath)
    }

    /// Get proxy path for a specific track
    /// - Parameter trackType: Track type ("screen" or "camera")
    /// - Returns: Path to proxy file if it exists, nil otherwise
    public func getProxyPath(for trackType: String) -> String? {
        guard let projectDir = projectDirectory else {
            return nil
        }

        let proxiesDirectory = (projectDir as NSString).appendingPathComponent("proxies")
        let proxyFileName = "\(trackType)_proxy.mov"
        let proxyPath = (proxiesDirectory as NSString).appendingPathComponent(proxyFileName)

        return FileManager.default.fileExists(atPath: proxyPath) ? proxyPath : nil
    }

    /// Delete all proxies for the current project
    /// - Throws: PreviewError if deletion fails
    public func deleteProxies() async throws {
        guard let projectDir = projectDirectory else {
            throw PreviewError.noProjectLoaded
        }

        let proxiesDirectory = (projectDir as NSString).appendingPathComponent("proxies")

        if FileManager.default.fileExists(atPath: proxiesDirectory) {
            try FileManager.default.removeItem(atPath: proxiesDirectory)
        }
    }

}
