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

    /// Shared instance
    public static let shared = Recorder()

    private var currentSession: RecordingSession?

    private let captureEngine = CaptureEngine.shared
    private let cameraEngine = CameraEngine.shared
    private let permissionManager = PermissionManager.shared

    // MARK: - Initialization

    private init() {}

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
                    outputURL: outputURL.appendingPathComponent("mic_audio.m4a")
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
            duration: session.duration,
            syncMetadata: syncMetadata,
            startTime: screenResult.startTime,
            endTime: screenResult.endTime
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

// MARK: - Mic Audio Recorder

/// Helper class for recording microphone audio
internal class MicAudioRecorder {
    private let outputURL: URL
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var isPaused = false
    private var startTime: Date?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func startRecording() async throws {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        // Get input node
        let inputNode = audioEngine.inputNode

        // Create recording format
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create audio file
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.audioFile = audioFile

        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { [weak self] buffer, when in
            guard let self = self, self.isRecording, !self.isPaused else {
                return
            }

            do {
                guard let audioFile = self.audioFile else { return }
                try audioFile.write(from: buffer)
            } catch {
                let log = Logger(subsystem: "com.projectstudio.enginekit", category: "MicAudioRecorder")
                log.error("Error writing audio buffer: \(error.localizedDescription)")
            }
        }

        // Start recording
        try audioEngine.start()
        self.isRecording = true
        self.startTime = Date()
    }

    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw Recorder.RecorderError.recordingNotStarted
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        isRecording = false
        audioEngine = nil

        return outputURL
    }

    func pauseRecording() async throws {
        guard isRecording, !isPaused else {
            throw Recorder.RecorderError.recordingNotStarted
        }
        isPaused = true
    }

    func resumeRecording() async throws {
        guard isRecording, isPaused else {
            throw Recorder.RecorderError.recordingNotStarted
        }
        isPaused = false
    }
}
