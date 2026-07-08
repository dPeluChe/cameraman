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
        /// Hide the system cursor in the capture stream. Use when synthetic
        /// cursor rendering is enabled so the real cursor doesn't double up.
        public let hideSystemCursor: Bool

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
            captureRect: CGRect? = nil,
            hideSystemCursor: Bool = false
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
            self.hideSystemCursor = hideSystemCursor
        }
    }

    /// Recording session.
    ///
    /// `@unchecked Sendable`: this class holds mutable state (writers,
    /// timestamps, error flags) but every read/write is funneled through
    /// the parent `CaptureEngine` actor — callers obtain the session via
    /// `actor`-isolated methods (`startRecording`/`stopRecording`/etc.)
    /// and the session never exposes setters publicly. Marking it as
    /// `@unchecked Sendable` lets the actor pass it across isolation
    /// boundaries without warnings under Swift 6 strict concurrency.
    /// If we ever expose mutation from outside the actor, this annotation
    /// must be removed and the session re-modeled (e.g. as its own actor).
    public final class RecordingSession: Identifiable, @unchecked Sendable {
        public let id: UUID
        public private(set) var isRecording: Bool = false
        public private(set) var startTime: Date?
        public private(set) var duration: TimeInterval = 0
        public private(set) var error: Error?
        public private(set) var videoWriterFailed: Bool = false
        public private(set) var audioWriterFailed: Bool = false

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

        internal func markVideoWriterFailed(_ error: Error?) {
            guard !videoWriterFailed else { return }
            videoWriterFailed = true
            if self.error == nil, let error = error {
                self.error = error
            }
        }

        internal func markAudioWriterFailed(_ error: Error?) {
            guard !audioWriterFailed else { return }
            audioWriterFailed = true
            if self.error == nil, let error = error {
                self.error = error
            }
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
        /// The video encoder failed mid-recording (e.g. VTEncoder malfunction under load
        /// or an unsupported resolution) — the output file is unusable.
        case recordingFailed(reason: String)

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
            case (.recordingFailed(let lhsReason), .recordingFailed(let rhsReason)):
                return lhsReason == rhsReason
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
            case .recordingFailed(let reason):
                return "Recording failed: \(reason)"
            }
        }
    }

    /// Result of a completed recording
    /// Note: Contains copied data from session to avoid Sendable issues
    public struct RecordingResult: Sendable {
        public let screenVideoPath: URL
        public let systemAudioPath: URL?
        public let duration: TimeInterval
        public let startTime: Date
        public let endTime: Date
        
        // Session data copied to avoid escaping actor reference
        public let sessionId: UUID
        public let sessionIsRecording: Bool
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

    var durationTimerTask: Task<Void, Never>?

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
        durationTimerTask?.cancel()
        durationTimerTask = nil

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
                let code = (error as NSError).code
                logger.error("Video writer error [code=\(code)]: \(error.localizedDescription)")
                // Track -10877 and other writer errors for diagnostics
                LogWarning(.capture, "Video writer error code \(code): \(error.localizedDescription)")
            }
        } else if let videoWriter = session.getVideoWriter() {
            logger.debug("Video writer already finalized with status: \(videoWriter.status.rawValue)")
        }

        logger.debug("Finalizing audio writer...")
        if let audioWriter = session.getAudioWriter(), audioWriter.status == .writing {
            await audioWriter.finishWriting()
            logger.debug("Audio writer status: \(audioWriter.status.rawValue)")
            if let error = audioWriter.error {
                let code = (error as NSError).code
                logger.error("Audio writer error [code=\(code)]: \(error.localizedDescription)")
                LogWarning(.capture, "Audio writer error code \(code): \(error.localizedDescription)")
            }
        } else if let audioWriter = session.getAudioWriter() {
            logger.debug("Audio writer already finalized with status: \(audioWriter.status.rawValue)")
        }
        
        // If the video encoder failed mid-recording the .mov is unusable (it opens as
        // "Cannot Open" in the editor). Surface it as a failed recording instead of
        // returning a corrupt file as if it succeeded.
        if let videoWriter = session.getVideoWriter(), videoWriter.status == .failed {
            let reason = videoWriter.error?.localizedDescription ?? "video encoder error"
            logger.error("Recording failed — video writer status .failed: \(reason)")
            throw CaptureError.recordingFailed(reason: reason)
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
            screenVideoPath: screenVideoPath,
            systemAudioPath: session.getAudioOutputURL(),
            duration: session.duration,
            startTime: session.startTime ?? Date(),
            endTime: Date(),
            sessionId: session.id,
            sessionIsRecording: session.isRecording
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
