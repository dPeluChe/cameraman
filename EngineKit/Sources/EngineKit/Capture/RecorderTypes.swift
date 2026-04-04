//
//  RecorderTypes.swift
//  EngineKit
//
//  Extracted from Recorder.swift — types, configuration, and errors
//

import Foundation
import AVFoundation

extension Recorder {
    /// Configuration for recording session
    public struct RecordingConfiguration {
        /// Screen capture configuration
        public let screenConfig: CaptureEngine.CaptureConfiguration
        /// Camera capture configuration (nil to skip camera)
        public let cameraConfig: CameraEngine.CameraConfiguration?
        /// Whether to capture microphone audio
        public let captureMicAudio: Bool
        /// Whether to capture cursor/click telemetry (always true by default)
        public let captureTelemetry: Bool
        /// Audio processing configuration (noise gate, echo cancellation)
        public let audioProcessing: AudioProcessingConfiguration

        public init(
            screenConfig: CaptureEngine.CaptureConfiguration,
            cameraConfig: CameraEngine.CameraConfiguration? = nil,
            captureMicAudio: Bool = false,
            captureTelemetry: Bool = true,
            audioProcessing: AudioProcessingConfiguration = .default
        ) {
            self.screenConfig = screenConfig
            self.cameraConfig = cameraConfig
            self.captureMicAudio = captureMicAudio
            self.captureTelemetry = captureTelemetry
            self.audioProcessing = audioProcessing
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
        internal var telemetrySession: TelemetryRecorder.RecordingSession?

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
        public let telemetryPath: URL?
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
}
