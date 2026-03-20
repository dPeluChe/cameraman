//
//  CameraEngineTypes.swift
//  EngineKit
//
//  Extracted from CameraEngine.swift — types, configuration, and errors
//

import Foundation
import AVFoundation

extension CameraEngine {
    /// Configuration for camera capture
    public struct CameraConfiguration {
        /// Camera device ID to use
        public let deviceID: String?
        /// Video resolution preset
        public let resolutionPreset: ResolutionPreset
        /// Frame rate for capture
        public let frameRate: Int
        /// Codec for recording
        public let codec: VideoCodec
        /// Sync offset in milliseconds (positive = delay camera relative to screen)
        public let syncOffsetMs: Double

        public enum ResolutionPreset {
            case hd720    // 1280x720
            case hd1080   // 1920x1080

            public var dimensions: (width: Int, height: Int) {
                switch self {
                case .hd720:
                    return (1280, 720)
                case .hd1080:
                    return (1920, 1080)
                }
            }
        }

        public enum VideoCodec {
            case h264
            case hevc

            var codecType: AVVideoCodecType {
                switch self {
                case .h264:
                    return .h264
                case .hevc:
                    return .hevc
                }
            }
        }

        public init(
            deviceID: String? = nil,
            resolutionPreset: ResolutionPreset = .hd1080,
            frameRate: Int = 30,
            codec: VideoCodec = .h264,
            syncOffsetMs: Double = 0
        ) {
            self.deviceID = deviceID
            self.resolutionPreset = resolutionPreset
            self.frameRate = frameRate
            self.codec = codec
            self.syncOffsetMs = syncOffsetMs
        }
    }

    /// Recording session
    public final class RecordingSession: Identifiable {
        public let id: UUID
        public private(set) var isRecording: Bool = false
        public private(set) var startTime: Date?
        public private(set) var duration: TimeInterval = 0
        public private(set) var error: Error?

        private var captureSession: AVCaptureSession?
        private var videoOutput: AVCaptureMovieFileOutput?
        private var assetWriter: AVAssetWriter?
        private var assetWriterInput: AVAssetWriterInput?
        private var outputURL: URL?
        private var sampleBufferDelegate: AnyObject?

        internal init(id: UUID = UUID()) {
            self.id = id
        }

        internal func setCaptureSession(_ session: AVCaptureSession) {
            self.captureSession = session
        }

        internal func setVideoOutput(_ output: AVCaptureMovieFileOutput) {
            self.videoOutput = output
        }

        internal func setAssetWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) {
            self.assetWriter = writer
            self.assetWriterInput = input
        }

        internal func setOutputURL(_ url: URL) {
            self.outputURL = url
        }

        internal func setSampleBufferDelegate(_ delegate: AnyObject) {
            self.sampleBufferDelegate = delegate
        }

        internal func markStarted(at time: Date) {
            self.startTime = time
            self.isRecording = true
        }

        internal func updateDuration(_ elapsed: TimeInterval) {
            self.duration = elapsed
        }

        internal func markStopped() {
            self.isRecording = false
        }

        internal func setError(_ error: Error) {
            self.error = error
            self.isRecording = false
        }

        internal func getCaptureSession() -> AVCaptureSession? { captureSession }
        internal func getVideoOutput() -> AVCaptureMovieFileOutput? { videoOutput }
        internal func getAssetWriter() -> AVAssetWriter? { assetWriter }
        internal func getAssetWriterInput() -> AVAssetWriterInput? { assetWriterInput }
        internal func getOutputURL() -> URL? { outputURL }
    }

    /// Errors that can occur during camera capture
    public enum CameraError: Error, LocalizedError, Equatable {
        case permissionDenied
        case cameraNotAvailable
        case deviceNotFound
        case failedToStartSession(underlying: Error)
        case failedToCreateAssetWriter(underlying: Error)
        case invalidConfiguration
        case recordingNotStarted
        case recordingAlreadyInProgress

        public static func == (lhs: CameraError, rhs: CameraError) -> Bool {
            switch (lhs, rhs) {
            case (.permissionDenied, .permissionDenied),
                 (.cameraNotAvailable, .cameraNotAvailable),
                 (.deviceNotFound, .deviceNotFound),
                 (.invalidConfiguration, .invalidConfiguration),
                 (.recordingNotStarted, .recordingNotStarted),
                 (.recordingAlreadyInProgress, .recordingAlreadyInProgress):
                return true
            case (.failedToStartSession(let lhsError), .failedToStartSession(let rhsError)),
                 (.failedToCreateAssetWriter(let lhsError), .failedToCreateAssetWriter(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Camera permission denied"
            case .cameraNotAvailable:
                return "Camera is not available on this device"
            case .deviceNotFound:
                return "Camera device not found"
            case .failedToStartSession(let error):
                return "Failed to start camera session: \(error.localizedDescription)"
            case .failedToCreateAssetWriter(let error):
                return "Failed to create asset writer: \(error.localizedDescription)"
            case .invalidConfiguration:
                return "Invalid camera configuration"
            case .recordingNotStarted:
                return "Recording has not been started"
            case .recordingAlreadyInProgress:
                return "Recording is already in progress"
            }
        }
    }

    /// Result of a completed recording
    public struct RecordingResult {
        public let session: RecordingSession
        public let cameraVideoPath: URL
        public let duration: TimeInterval
        public let syncOffsetMs: Double
        public let startTime: Date
        public let endTime: Date
    }

    /// Available camera device
    public struct CameraDevice: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let localizedName: String
        public let position: AVCaptureDevice.Position?

        public init(
            id: String,
            name: String,
            localizedName: String,
            position: AVCaptureDevice.Position?
        ) {
            self.id = id
            self.name = name
            self.localizedName = localizedName
            self.position = position
        }
    }
}
