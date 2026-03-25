//
//  CaptureEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import os.log

/// CaptureEngine manages screen and audio recording using ScreenCaptureKit
public actor CaptureEngine {
    let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "CaptureEngine")
    // MARK: - Types

    /// Configuration for capturing a specific source
    public struct CaptureConfiguration {
        /// Source type to capture
        public let sourceType: SourceType
        /// Display info (for display capture)
        public let display: SourceSelector.DisplaySource?
        /// Window info (for window capture)
        public let window: SourceSelector.WindowSource?
        /// Application info (for application capture)
        public let application: SourceSelector.ApplicationSource?
        /// Whether to capture system audio
        public let captureSystemAudio: Bool
        /// Frame rate for video capture
        public let frameRate: Int
        /// Output pixel format
        public let pixelFormat: OSType
        /// Output quality preset (scales down from native, never upscales)
        public let quality: RecordingQuality
        /// Capture only this region of the display, in display points with top-left origin.
        /// nil = full display.
        public let captureRect: CGRect?

        public enum SourceType {
            case display
            case window
            case application
        }

        public init(
            sourceType: SourceType,
            display: SourceSelector.DisplaySource? = nil,
            window: SourceSelector.WindowSource? = nil,
            application: SourceSelector.ApplicationSource? = nil,
            captureSystemAudio: Bool = false,
            frameRate: Int = 60,
            pixelFormat: OSType = kCVPixelFormatType_32BGRA,
            quality: RecordingQuality = .native,
            captureRect: CGRect? = nil
        ) {
            self.sourceType = sourceType
            self.display = display
            self.window = window
            self.application = application
            self.captureSystemAudio = captureSystemAudio
            self.frameRate = frameRate
            self.pixelFormat = pixelFormat
            self.quality = quality
            self.captureRect = captureRect
        }
    }

    /// Recording session
    public final class RecordingSession: Identifiable {
        public let id: UUID
        public private(set) var isRecording: Bool = false
        public private(set) var startTime: Date?
        public private(set) var duration: TimeInterval = 0
        public private(set) var error: Error?

        private var outputStream: SCStream?
        private var videoOutput: AVAssetWriter?
        private var audioOutput: AVAssetWriter?
        private var videoInput: AVAssetWriterInput?
        private var audioInput: AVAssetWriterInput?
        private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        private var sessionStartTime: CMTime?
        private var firstVideoTimestamp: CMTime?
        private var firstAudioTimestamp: CMTime?
        private var videoOutputURL: URL?
        private var audioOutputURL: URL?

        internal init(id: UUID = UUID()) {
            self.id = id
        }

        internal func setStream(_ stream: SCStream) {
            self.outputStream = stream
        }

        internal func setVideoWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
            self.videoOutput = writer
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
            self.videoOutputURL = writer.outputURL
        }

        internal func setAudioWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) {
            self.audioOutput = writer
            self.audioInput = input
            self.audioOutputURL = writer.outputURL
        }

        internal func markStarted(at time: Date) {
            self.startTime = time
            self.isRecording = true
            self.sessionStartTime = CMTime(seconds: 0, preferredTimescale: 600)
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

        internal func getVideoWriter() -> AVAssetWriter? { videoOutput }
        internal func getAudioWriter() -> AVAssetWriter? { audioOutput }
        internal func getVideoInput() -> AVAssetWriterInput? { videoInput }
        internal func getAudioInput() -> AVAssetWriterInput? { audioInput }
        internal func getPixelBufferAdaptor() -> AVAssetWriterInputPixelBufferAdaptor? { pixelBufferAdaptor }
        internal func getSessionStartTime() -> CMTime? { sessionStartTime }
        internal func getFirstVideoTimestamp() -> CMTime? { firstVideoTimestamp }
        internal func setFirstVideoTimestamp(_ timestamp: CMTime) { firstVideoTimestamp = timestamp }
        internal func getFirstAudioTimestamp() -> CMTime? { firstAudioTimestamp }
        internal func setFirstAudioTimestamp(_ timestamp: CMTime) { firstAudioTimestamp = timestamp }
        internal func getStream() -> SCStream? { outputStream }
        internal func getVideoOutputURL() -> URL? { videoOutputURL }
        internal func getAudioOutputURL() -> URL? { audioOutputURL }
    }

    /// Errors that can occur during capture
    public enum CaptureError: Error, LocalizedError, Equatable {
        case permissionDenied
        case noSourceSelected
        case failedToStartStream(underlying: Error)
        case failedToCreateAssetWriter(underlying: Error)
        case failedToSetupAudio(underlying: Error)
        case invalidConfiguration
        case recordingNotStarted
        case recordingAlreadyInProgress

        public static func == (lhs: CaptureError, rhs: CaptureError) -> Bool {
            switch (lhs, rhs) {
            case (.permissionDenied, .permissionDenied),
                 (.noSourceSelected, .noSourceSelected),
                 (.invalidConfiguration, .invalidConfiguration),
                 (.recordingNotStarted, .recordingNotStarted),
                 (.recordingAlreadyInProgress, .recordingAlreadyInProgress):
                return true
            case (.failedToStartStream(let lhsError), .failedToStartStream(let rhsError)),
                 (.failedToCreateAssetWriter(let lhsError), .failedToCreateAssetWriter(let rhsError)),
                 (.failedToSetupAudio(let lhsError), .failedToSetupAudio(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen recording permission denied"
            case .noSourceSelected:
                return "No capture source selected"
            case .failedToStartStream(let error):
                return "Failed to start capture stream: \(error.localizedDescription)"
            case .failedToCreateAssetWriter(let error):
                return "Failed to create asset writer: \(error.localizedDescription)"
            case .failedToSetupAudio(let error):
                return "Failed to setup audio capture: \(error.localizedDescription)"
            case .invalidConfiguration:
                return "Invalid capture configuration"
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
        public let screenVideoPath: URL
        public let systemAudioPath: URL?
        public let duration: TimeInterval
        public let startTime: Date
        public let endTime: Date
    }

    // MARK: - Properties

    /// Shared instance
    public static let shared = CaptureEngine()

    var currentSession: RecordingSession?

    let sourceSelector = SourceSelector.shared
    let permissionManager = PermissionManager.shared
    
    var streamDelegate: StreamDelegate?
    var videoStreamOutput: CaptureStreamOutput?
    var audioStreamOutput: CaptureStreamOutput?
    
    // Debug counters
    var videoFrameCount = 0
    var audioFrameCount = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start a recording session with the given configuration
    /// - Parameters:
    ///   - config: Capture configuration
    ///   - outputURL: Base URL for output files
    /// - Returns: RecordingSession
    public func startRecording(
        config: CaptureConfiguration,
        outputURL: URL
    ) async throws -> RecordingSession {
        // Check if recording is already in progress
        guard currentSession == nil else {
            throw CaptureError.recordingAlreadyInProgress
        }

        // Check permissions
        let healthCheck = await permissionManager.performHealthCheck()
        guard healthCheck.canRecord(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        ) else {
            throw CaptureError.permissionDenied
        }

        // Validate configuration
        try validateConfiguration(config)

        // Create session
        let session = RecordingSession()
        currentSession = session

        // Setup capture
        let (streamConfig, filter) = try await setupStreamConfiguration(config)

        // Create asset writers
        // Note: outputURL is already the full path to screen.mov (passed from Recorder.swift)
        // We need to derive the base directory for system_audio.m4a
        let screenVideoURL = outputURL
        let baseDirectory = outputURL.deletingLastPathComponent()
        let systemAudioURL = config.captureSystemAudio ? baseDirectory.appendingPathComponent("system_audio.m4a") : nil

        // streamConfig already has the correct output dimensions (computed in setupStreamConfiguration)
        let (videoWriter, pixelBufferAdaptor) = try await createVideoWriter(
            outputURL: screenVideoURL,
            width: streamConfig.width,
            height: streamConfig.height,
            frameRate: config.frameRate
        )

        guard let videoInput = videoWriter.inputs.first else {
            throw CaptureError.failedToCreateAssetWriter(underlying: NSError(domain: "CaptureEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video writer has no inputs"]))
        }
        session.setVideoWriter(videoWriter, input: videoInput, adaptor: pixelBufferAdaptor)

        if config.captureSystemAudio, let audioURL = systemAudioURL {
            let audioWriter = try await createAudioWriter(outputURL: audioURL)
            guard let audioInput = audioWriter.inputs.first else {
                throw CaptureError.failedToCreateAssetWriter(underlying: NSError(domain: "CaptureEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio writer has no inputs"]))
            }
            session.setAudioWriter(audioWriter, input: audioInput)
        }

        // Create and start stream
        let stream = try await startStream(configuration: streamConfig, filter: filter)
        session.setStream(stream)

        // Start recording
        session.markStarted(at: Date())
        
        // Reset frame counters
        videoFrameCount = 0
        audioFrameCount = 0
        logger.debug("Frame counters reset")

        // Start timer for duration tracking
        startDurationTimer(for: session)

        return session
    }

    /// Stop the current recording session
    /// - Parameter session: The session to stop
    /// - Returns: RecordingResult with paths to recorded files
    public func stopRecording(session: RecordingSession) async throws -> RecordingResult {
        guard currentSession?.id == session.id else {
            throw CaptureError.recordingNotStarted
        }

        guard session.isRecording else {
            throw CaptureError.recordingNotStarted
        }

        // Mark as stopped IMMEDIATELY to prevent double calls
        session.markStopped()

        logger.debug("Stopping stream...")
        // Stop stream
        if let stream = session.getStream() {
            try? await stream.stopCapture()
        }
        logger.debug("Stream stopped")

        logger.debug("Finalizing video writer...")
        // Mark inputs as finished BEFORE finalizing writers
        if let videoInput = session.getVideoInput() {
            videoInput.markAsFinished()
        }
        if let audioInput = session.getAudioInput() {
            audioInput.markAsFinished()
        }
        
        // Finalize writers - Check status first to avoid double finalization
        if let videoWriter = session.getVideoWriter(), videoWriter.status == .writing {
            await videoWriter.finishWriting()
            logger.debug("Video writer status: \(videoWriter.status.rawValue)")
            if let error = videoWriter.error {
                logger.error("Video writer error: \(error.localizedDescription)")
            }
        } else if let videoWriter = session.getVideoWriter() {
            logger.debug("Video writer already finalized with status: \(videoWriter.status.rawValue)")
        }

        logger.debug("Finalizing audio writer...")
        if let audioWriter = session.getAudioWriter(), audioWriter.status == .writing {
            await audioWriter.finishWriting()
            logger.debug("Audio writer status: \(audioWriter.status.rawValue)")
            if let error = audioWriter.error {
                logger.error("Audio writer error: \(error.localizedDescription)")
            }
        } else if let audioWriter = session.getAudioWriter() {
            logger.debug("Audio writer already finalized with status: \(audioWriter.status.rawValue)")
        }
        
        // Print frame statistics
        logger.debug("Total video frames: \(self.videoFrameCount)")
        logger.debug("Total audio frames: \(self.audioFrameCount)")

        // Get output paths from session (these are the real paths where files were created)
        guard let screenVideoPath = session.getVideoOutputURL() else {
            throw CaptureError.recordingNotStarted
        }

        logger.debug("Video output path: \(screenVideoPath.path)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: screenVideoPath.path)
        logger.debug("Video file exists: \(fileExists)")
        
        if fileExists {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: screenVideoPath.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    logger.debug("Video file size: \(fileSize.int64Value) bytes")
                }
            } catch {
                logger.error("Failed to get file attributes: \(error.localizedDescription)")
            }
        }

        let result = RecordingResult(
            session: session,
            screenVideoPath: screenVideoPath,
            systemAudioPath: session.getAudioOutputURL(),
            duration: session.duration,
            startTime: session.startTime ?? Date(),
            endTime: Date()
        )

        currentSession = nil

        return result
    }

    /// Pause the current recording session
    public func pauseRecording(session: RecordingSession) async throws {
        guard currentSession?.id == session.id else {
            throw CaptureError.recordingNotStarted
        }

        // Pause stream
        if let stream = session.getStream() {
            try? await stream.stopCapture()
        }
    }

    /// Resume the current recording session
    public func resumeRecording(session: RecordingSession) async throws {
        guard currentSession?.id == session.id else {
            throw CaptureError.recordingNotStarted
        }

        // Resume stream
        // Note: ScreenCaptureKit doesn't support pause/resume directly
        // We would need to stop and restart with proper time offset handling
        throw CaptureError.recordingNotStarted
    }

}
