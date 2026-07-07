//
//  Recorder.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import os.log

/// Recorder coordinates multi-track recording (screen, camera, system audio, mic)
public actor Recorder {
    private let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "Recorder")
    // MARK: - Properties

    /// Shared instance using default singletons
    public static let shared = Recorder()

    private var currentSession: RecordingSession?

    private let captureEngine: CaptureEngine
    private let cameraEngine: CameraEngine
    private let permissionManager: PermissionManager
    
    /// Telemetry recorder instance
    private var telemetryRecorder: TelemetryRecorder?

    // MARK: - Initialization

    /// Initialize with custom engines (for testing or DI)
    public init(
        captureEngine: CaptureEngine = .shared,
        cameraEngine: CameraEngine = .shared,
        permissionManager: PermissionManager = .shared
    ) {
        self.captureEngine = captureEngine
        self.cameraEngine = cameraEngine
        self.permissionManager = permissionManager
    }
    
    /// Initialize from EngineContext
    public init(context: EngineContext) {
        self.captureEngine = context.captureEngine
        self.cameraEngine = context.cameraEngine
        self.permissionManager = context.permissionManager
    }

    // MARK: - Public API

    /// Start a recording session with the given configuration
    /// - Parameters:
    ///   - config: Recording configuration
    ///   - outputURL: Base URL for output files
    /// - Returns: RecordingSession
    public func startRecording(
        config: RecordingConfiguration,
        outputURL: URL
    ) async throws -> RecordingSession {
        // Check if a session is already in progress
        guard currentSession == nil else {
            throw RecorderError.recordingAlreadyInProgress
        }

        // Validate permissions
        let healthCheck = await permissionManager.performHealthCheck()
        let canRecord = healthCheck.canRecord(
            needsScreenRecording: true,
            needsMicrophone: config.captureMicAudio,
            needsCamera: config.cameraConfig != nil
        )

        guard canRecord else {
            _ = healthCheck.missingPermissions(
                needsScreenRecording: true,
                needsMicrophone: config.captureMicAudio,
                needsCamera: config.cameraConfig != nil
            )
            throw RecorderError.permissionDenied
        }

        // Create output directory
        do {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecorderError.failedToCreateOutputDirectory(error)
        }

        // Create recording session
        let session = RecordingSession()
        currentSession = session

        // Resolve capture geometry up front (display frame + area rect + scale) so
        // cursor telemetry can be mapped onto the recorded video later. NSScreen
        // requires the main actor.
        session.captureGeometry = await MainActor.run {
            CaptureGeometry.from(config: config.screenConfig)
        }

        // Start screen capture
        let screenSession = try await captureEngine.startRecording(
            config: config.screenConfig,
            outputURL: outputURL.appendingPathComponent("screen.mov")
        )
        session.setScreenSession(screenSession)

        // Start camera capture if configured
        if let cameraConfig = config.cameraConfig {
            do {
                let cameraSession = try await cameraEngine.startRecording(
                    config: cameraConfig,
                    outputURL: outputURL.appendingPathComponent("camera.mov")
                )
                session.setCameraSession(cameraSession, config: cameraConfig)
            } catch {
                // Cleanup screen capture if camera fails
                _ = try? await captureEngine.stopRecording(session: screenSession)
                currentSession = nil
                throw RecorderError.failedToStartCameraCapture(error)
            }
        }

        // Start mic audio capture if configured
        if config.captureMicAudio {
            do {
                let micRecorder = MicAudioRecorder(
                    outputURL: outputURL.appendingPathComponent("mic_audio.m4a"),
                    audioProcessing: config.audioProcessing
                )
                try await micRecorder.startRecording()
                session.setMicAudioSession(micRecorder)
            } catch {
                // Cleanup other captures if mic fails
                _ = try? await cleanupSession(session)
                currentSession = nil
                throw RecorderError.failedToStartMicCapture(error)
            }
        }

        // Start cursor telemetry (always on by default)
        if config.captureTelemetry {
            do {
                let telemetryDir = outputURL.appendingPathComponent("telemetry")
                try FileManager.default.createDirectory(at: telemetryDir, withIntermediateDirectories: true)
                let telemetryConfig = TelemetryRecorder.Configuration(
                    outputDirectory: telemetryDir
                )
                let recorder = TelemetryRecorder()
                let telemetrySession = try await recorder.startRecording(config: telemetryConfig)
                session.telemetrySession = telemetrySession
                logger.info("Telemetry recording started")
            } catch {
                logger.warning("Failed to start telemetry recording: \(error.localizedDescription)")
                // Non-fatal: continue recording without telemetry
            }
        }

        // Mark session as started
        session.markStarted(at: Date())

        return session
    }

    /// Stop a recording session and return the result
    /// - Parameter session: Recording session to stop
    /// - Returns: RecordingResult with file paths and metadata
    public func stopRecording(session: RecordingSession) async throws -> RecordingResult {
        // Verify this is the current session
        guard currentSession?.id == session.id else {
            throw RecorderError.sessionNotFound
        }

        guard session.isRecording else {
            throw RecorderError.recordingNotStarted
        }

        var screenResult: CaptureEngine.RecordingResult?
        var cameraResult: CameraEngine.RecordingResult?
        var micAudioPath: URL?
        var telemetryPath: URL?

        // Stop all captures
        if let screenSession = session.getScreenSession() {
            do {
                screenResult = try await captureEngine.stopRecording(session: screenSession)
            } catch {
                session.setError(error)
            }
        }

        if let (cameraSession, cameraConfig) = session.getCameraSession() {
            do {
                cameraResult = try await cameraEngine.stopRecording(
                    session: cameraSession,
                    config: cameraConfig
                )
            } catch {
                session.setError(error)
            }
        }

        if let micRecorder = session.micAudioSession {
            do {
                micAudioPath = try await micRecorder.stopRecording()
            } catch {
                session.setError(error)
            }
        }

        // Stop telemetry
        if let telemetrySession = session.telemetrySession {
            telemetryPath = telemetrySession.config.outputDirectory.appendingPathComponent("cursor.jsonl")
            logger.info("Telemetry recording stopped: \(telemetrySession.eventCount) events")
        }

        // Mark session as ended
        session.markEnded(at: Date())

        // Clear current session
        currentSession = nil

        // Build sync metadata
        let syncMetadata = SyncMetadata(
            cameraSyncOffsetMs: cameraResult?.syncOffsetMs ?? 0,
            micAudioSyncOffsetMs: 0, // Mic audio starts at same time as screen
            systemAudioSyncOffsetMs: 0, // System audio is synced with screen
            syncReference: "screen"
        )

        // Create recording result
        guard let screenResult = screenResult else {
            throw RecorderError.recordingNotStarted
        }

        let result = RecordingResult(
            session: session,
            screenVideoPath: screenResult.screenVideoPath,
            systemAudioPath: screenResult.systemAudioPath,
            cameraVideoPath: cameraResult?.cameraVideoPath,
            micAudioPath: micAudioPath,
            telemetryPath: telemetryPath,
            duration: session.duration,
            syncMetadata: syncMetadata,
            startTime: screenResult.startTime,
            endTime: screenResult.endTime,
            captureGeometry: session.captureGeometry
        )

        return result
    }

    /// Pause a recording session
    /// - Parameter session: Recording session to pause
    public func pauseRecording(session: RecordingSession) async throws {
        guard currentSession?.id == session.id else {
            throw RecorderError.sessionNotFound
        }

        guard session.isRecording, !session.isPaused else {
            throw RecorderError.recordingNotStarted
        }

        // Pause screen capture
        if let screenSession = session.getScreenSession() {
            try await captureEngine.pauseRecording(session: screenSession)
        }

        // Note: CameraEngine doesn't support pause/resume, so camera continues recording
        // This is a known limitation - camera track will be longer than screen track

        // Pause mic audio
        if let micRecorder = session.micAudioSession {
            try await micRecorder.pauseRecording()
        }

        session.markPaused()
    }

    /// Resume a paused recording session
    /// - Parameter session: Recording session to resume
    public func resumeRecording(session: RecordingSession) async throws {
        guard currentSession?.id == session.id else {
            throw RecorderError.sessionNotFound
        }

        guard session.isRecording, session.isPaused else {
            throw RecorderError.recordingNotStarted
        }

        // Resume screen capture
        if let screenSession = session.getScreenSession() {
            try await captureEngine.resumeRecording(session: screenSession)
        }

        // Note: CameraEngine doesn't support pause/resume

        // Resume mic audio
        if let micRecorder = session.micAudioSession {
            try await micRecorder.resumeRecording()
        }

        session.markResumed()
    }

    /// Get the current recording session
    /// - Returns: Current RecordingSession if any
    public func getCurrentSession() -> RecordingSession? {
        return currentSession
    }

    // MARK: - Private Helpers

    private func cleanupSession(_ session: RecordingSession) async throws {
        if let screenSession = session.getScreenSession() {
            _ = try? await captureEngine.stopRecording(session: screenSession)
        }
        if let (cameraSession, cameraConfig) = session.getCameraSession() {
            _ = try? await cameraEngine.stopRecording(
                session: cameraSession,
                config: cameraConfig
            )
        }
        if let micRecorder = session.micAudioSession {
            _ = try? await micRecorder.stopRecording()
        }
    }
}
