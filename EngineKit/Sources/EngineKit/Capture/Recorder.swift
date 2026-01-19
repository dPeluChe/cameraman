//
//  Recorder.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// Recorder coordinates multi-track recording (screen, camera, system audio, mic)
public actor Recorder {
    // MARK: - Types

    /// Configuration for recording session
    public struct RecordingConfiguration {
        /// Screen capture configuration
        public let screenConfig: CaptureEngine.CaptureConfiguration
        /// Camera capture configuration (nil to skip camera)
        public let cameraConfig: CameraEngine.CameraConfiguration?
        /// Whether to capture microphone audio
        public let captureMicAudio: Bool

        public init(
            screenConfig: CaptureEngine.CaptureConfiguration,
            cameraConfig: CameraEngine.CameraConfiguration? = nil,
            captureMicAudio: Bool = false
        ) {
            self.screenConfig = screenConfig
            self.cameraConfig = cameraConfig
            self.captureMicAudio = captureMicAudio
        }
    }

    /// Active recording session
    public final class RecordingSession: Identifiable {
        public let id: UUID
        public private(set) var isRecording: Bool = false
        public private(set) var isPaused: Bool = false
        public private(set) var startTime: Date?
        public private(set) var endTime: Date?
        public private(set) var duration: TimeInterval = 0
        public private(set) var error: Error?

        private var screenSession: CaptureEngine.RecordingSession?
        private var cameraSession: CameraEngine.RecordingSession?
        private var cameraConfig: CameraEngine.CameraConfiguration?
        internal var micAudioSession: MicAudioRecorder?

        internal init(id: UUID = UUID()) {
            self.id = id
        }

        internal func setScreenSession(_ session: CaptureEngine.RecordingSession) {
            self.screenSession = session
        }

        internal func setCameraSession(_ session: CameraEngine.RecordingSession, config: CameraEngine.CameraConfiguration) {
            self.cameraSession = session
            self.cameraConfig = config
        }

        internal func setMicAudioSession(_ session: MicAudioRecorder) {
            self.micAudioSession = session
        }

        internal func markStarted(at time: Date) {
            self.startTime = time
            self.isRecording = true
        }

        internal func markEnded(at time: Date) {
            self.endTime = time
            self.isRecording = false
            if let start = startTime {
                self.duration = time.timeIntervalSince(start)
            }
        }

        internal func updateDuration(_ elapsed: TimeInterval) {
            self.duration = elapsed
        }

        internal func markPaused() {
            self.isPaused = true
        }

        internal func markResumed() {
            self.isPaused = false
        }

        internal func setError(_ error: Error) {
            self.error = error
            self.isRecording = false
        }

        internal func getScreenSession() -> CaptureEngine.RecordingSession? {
            return screenSession
        }

        internal func getCameraSession() -> (session: CameraEngine.RecordingSession, config: CameraEngine.CameraConfiguration)? {
            guard let session = cameraSession, let config = cameraConfig else {
                return nil
            }
            return (session, config)
        }

        private func getMicAudioSession() -> MicAudioRecorder? {
            return micAudioSession
        }
    }

    /// Result of a completed recording
    public struct RecordingResult {
        public let session: RecordingSession
        public let screenVideoPath: URL
        public let systemAudioPath: URL?
        public let cameraVideoPath: URL?
        public let micAudioPath: URL?
        public let duration: TimeInterval
        public let syncMetadata: SyncMetadata
        public let startTime: Date
        public let endTime: Date

        public func dumpMetadata(to url: URL) throws {
            let metadata: [String: Any] = [
                "session_id": session.id.uuidString,
                "start_time": ISO8601DateFormatter().string(from: startTime),
                "end_time": ISO8601DateFormatter().string(from: endTime),
                "duration": duration,
                "screen": [
                    "path": screenVideoPath.path,
                    "has_system_audio": systemAudioPath != nil
                ],
                "camera": cameraVideoPath.map { path in
                    [
                        "path": path.path,
                        "sync_offset_ms": syncMetadata.cameraSyncOffsetMs
                    ]
                } as Any,
                "mic_audio": micAudioPath.map { path in
                    [
                        "path": path.path,
                        "sync_offset_ms": syncMetadata.micAudioSyncOffsetMs
                    ]
                } as Any
            ]

            let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            try data.write(to: url)
        }
    }

    /// Synchronization metadata for multi-track alignment
    public struct SyncMetadata: Codable {
        /// Camera sync offset in milliseconds (positive = camera delayed relative to screen)
        public let cameraSyncOffsetMs: Double
        /// Mic audio sync offset in milliseconds
        public let micAudioSyncOffsetMs: Double
        /// System audio sync offset in milliseconds
        public let systemAudioSyncOffsetMs: Double
        /// Sync reference track (usually "screen")
        public let syncReference: String

        public init(
            cameraSyncOffsetMs: Double = 0,
            micAudioSyncOffsetMs: Double = 0,
            systemAudioSyncOffsetMs: Double = 0,
            syncReference: String = "screen"
        ) {
            self.cameraSyncOffsetMs = cameraSyncOffsetMs
            self.micAudioSyncOffsetMs = micAudioSyncOffsetMs
            self.systemAudioSyncOffsetMs = systemAudioSyncOffsetMs
            self.syncReference = syncReference
        }
    }

    /// Recorder-specific errors
    public enum RecorderError: LocalizedError {
        case permissionDenied
        case invalidConfiguration
        case failedToStartScreenCapture(Error)
        case failedToStartCameraCapture(Error)
        case failedToStartMicCapture(Error)
        case recordingNotStarted
        case recordingAlreadyInProgress
        case sessionNotFound
        case failedToCreateOutputDirectory(Error)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Required permissions not granted for recording"
            case .invalidConfiguration:
                return "Invalid recording configuration"
            case .failedToStartScreenCapture(let error):
                return "Failed to start screen capture: \(error.localizedDescription)"
            case .failedToStartCameraCapture(let error):
                return "Failed to start camera capture: \(error.localizedDescription)"
            case .failedToStartMicCapture(let error):
                return "Failed to start microphone capture: \(error.localizedDescription)"
            case .recordingNotStarted:
                return "Recording has not been started"
            case .recordingAlreadyInProgress:
                return "Recording is already in progress"
            case .sessionNotFound:
                return "Recording session not found"
            case .failedToCreateOutputDirectory(let error):
                return "Failed to create output directory: \(error.localizedDescription)"
            }
        }
    }

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
                print("Error writing audio buffer: \(error)")
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
