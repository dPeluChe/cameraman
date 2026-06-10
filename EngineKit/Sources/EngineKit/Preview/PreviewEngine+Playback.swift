//
//  PreviewEngine+Playback.swift
//  EngineKit
//
//  Playback control, time observation, state queries, and proxy management.
//  Extracted from PreviewEngine.swift.
//

import Foundation
import AVFoundation

extension PreviewEngine {

    // MARK: - Playback Control

    /// Start playback from current position
    public func play() async throws {
        guard let project = project else {
            throw PreviewError.noProjectLoaded
        }

        guard project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) else {
            throw PreviewError.noSegments
        }

        player?.play()
        playbackState = .playing
        playbackRate = 1.0

        startPeriodicTimeObservation()
    }

    /// Pause playback
    public func pause() async throws {
        guard player != nil else {
            throw PreviewError.noProjectLoaded
        }

        player?.pause()
        playbackState = .paused
        stopPeriodicTimeObservation()
    }

    /// Stop playback and reset to beginning
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
    public func setLooping(_ enabled: Bool) {
        loopEnabled = enabled
    }

    // MARK: - Time Observation

    func updateCurrentTime(_ time: TimeInterval) {
        self.currentTime = time
    }

    func startPeriodicTimeObservation() {
        guard let player = player else { return }

        stopPeriodicTimeObservation()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task {
                await self.updateCurrentTime(time.seconds)
            }
        }
    }

    func stopPeriodicTimeObservation() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    // MARK: - State Query

    /// Get current preview session information
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

    public func getCurrentTime() -> TimeInterval { currentTime }
    public func getDuration() -> TimeInterval { project?.timeline.duration ?? 0 }
    public func getPlaybackState() -> PlaybackState { playbackState }
    public func isPlaying() -> Bool { playbackState == .playing }
    public func isPaused() -> Bool { playbackState == .paused }
    public func isStopped() -> Bool { playbackState == .stopped }

    // MARK: - Proxy Management

    /// Generate proxies for the current project
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
    public func hasProxies() -> Bool {
        guard project != nil, let projectDir = projectDirectory else { return false }
        let screenProxyPath = (projectDir as NSString).appendingPathComponent("proxies/screen_proxy.mov")
        return FileManager.default.fileExists(atPath: screenProxyPath)
    }

    /// Get proxy path for a specific track
    public func getProxyPath(for trackType: String) -> String? {
        guard let projectDir = projectDirectory else { return nil }
        let proxyPath = (projectDir as NSString)
            .appendingPathComponent("proxies")
            .appending("/\(trackType)_proxy.mov")
        return FileManager.default.fileExists(atPath: proxyPath) ? proxyPath : nil
    }

    /// Delete all proxies for the current project
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
