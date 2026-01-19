//
//  CaptureEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import ScreenCaptureKit
import AVFoundation

/// CaptureEngine manages screen and audio recording using ScreenCaptureKit
public actor CaptureEngine {
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
            pixelFormat: OSType = kCVPixelFormatType_32BGRA
        ) {
            self.sourceType = sourceType
            self.display = display
            self.window = window
            self.application = application
            self.captureSystemAudio = captureSystemAudio
            self.frameRate = frameRate
            self.pixelFormat = pixelFormat
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
        private var sessionStartTime: CMTime?

        internal init(id: UUID = UUID()) {
            self.id = id
        }

        internal func setStream(_ stream: SCStream) {
            self.outputStream = stream
        }

        internal func setVideoWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) {
            self.videoOutput = writer
            self.videoInput = input
        }

        internal func setAudioWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) {
            self.audioOutput = writer
            self.audioInput = input
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
        internal func getSessionStartTime() -> CMTime? { sessionStartTime }
        internal func getStream() -> SCStream? { outputStream }
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

    private var currentSession: RecordingSession?

    private let sourceSelector = SourceSelector.shared
    private let permissionManager = PermissionManager.shared

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
        let screenVideoURL = outputURL.appendingPathComponent("screen.mov")
        let systemAudioURL = config.captureSystemAudio ? outputURL.appendingPathComponent("system_audio.m4a") : nil

        let videoWriter = try await createVideoWriter(
            outputURL: screenVideoURL,
            width: config.display?.width ?? 1920,
            height: config.display?.height ?? 1080,
            frameRate: config.frameRate
        )

        session.setVideoWriter(videoWriter, input: videoWriter.inputs.first!)

        if config.captureSystemAudio, let audioURL = systemAudioURL {
            let audioWriter = try await createAudioWriter(outputURL: audioURL)
            session.setAudioWriter(audioWriter, input: audioWriter.inputs.first!)
        }

        // Create and start stream
        let stream = try await startStream(configuration: streamConfig, filter: filter)
        session.setStream(stream)

        // Start recording
        session.markStarted(at: Date())

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

        session.markStopped()

        // Stop stream
        if let stream = session.getStream() {
            try? await stream.stopCapture()
        }

        // Finalize writers
        if let videoWriter = session.getVideoWriter() {
            await videoWriter.finishWriting()
        }

        if let audioWriter = session.getAudioWriter() {
            await audioWriter.finishWriting()
        }

        // Get output paths
        let outputPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("recordings")
            .appendingPathComponent(session.id.uuidString)

        let screenVideoPath = outputPath.appendingPathComponent("screen.mov")
        let systemAudioPath = outputPath.appendingPathComponent("system_audio.m4a")

        let result = RecordingResult(
            session: session,
            screenVideoPath: screenVideoPath,
            systemAudioPath: session.getAudioWriter() != nil ? systemAudioPath : nil,
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

    // MARK: - Private Helpers

    private func validateConfiguration(_ config: CaptureConfiguration) throws {
        switch config.sourceType {
        case .display:
            guard config.display != nil else {
                throw CaptureError.invalidConfiguration
            }
        case .window:
            guard config.window != nil else {
                throw CaptureError.invalidConfiguration
            }
        case .application:
            guard config.application != nil else {
                throw CaptureError.invalidConfiguration
            }
        }
    }

    private func setupStreamConfiguration(
        _ config: CaptureConfiguration
    ) async throws -> (SCStreamConfiguration, SCContentFilter) {
        let streamConfig = SCStreamConfiguration()

        // Set dimensions based on source
        let width: Int
        let height: Int

        switch config.sourceType {
        case .display:
            width = config.display?.width ?? 1920
            height = config.display?.height ?? 1080
        case .window:
            width = config.window?.width ?? 1920
            height = config.window?.height ?? 1080
        case .application:
            width = 1920
            height = 1080
        }

        streamConfig.width = width
        streamConfig.height = height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.pixelFormat = config.pixelFormat
        streamConfig.capturesAudio = config.captureSystemAudio

        // Setup content filter
        let contentFilter: SCContentFilter

        switch config.sourceType {
        case .display:
            // Get available displays
            let displays = try await sourceSelector.listDisplays()
            guard let targetDisplay = displays.first(where: { $0.id == config.display?.id }) else {
                throw CaptureError.noSourceSelected
            }

            // Create filter for entire display
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            contentFilter = SCContentFilter(display: shareableContent.displays.first(where: { display in
                // Match display by some criteria
                return true
            })!, excludingWindows: [])

        case .window:
            let windows = try await sourceSelector.listWindows()
            guard let targetWindow = windows.first(where: { $0.id == config.window?.id }) else {
                throw CaptureError.noSourceSelected
            }

            // Create filter for specific window
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            guard let scWindow = shareableContent.windows.first(where: { window in
                String(window.windowID) == targetWindow.id
            }) else {
                throw CaptureError.noSourceSelected
            }

            contentFilter = SCContentFilter(desktopIndependentWindow: scWindow)

        case .application:
            let applications = try await sourceSelector.listApplications()
            guard let targetApp = applications.first(where: { $0.id == config.application?.id }) else {
                throw CaptureError.noSourceSelected
            }

            // Create filter for application
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            guard let app = shareableContent.applications.first(where: { application in
                application.bundleIdentifier == targetApp.bundleIdentifier
            }) else {
                throw CaptureError.noSourceSelected
            }

            // Get all windows for this application
            let appWindows = shareableContent.windows.filter { window in
                window.owningApplication?.bundleIdentifier == app.bundleIdentifier
            }

            contentFilter = SCContentFilter(desktopIndependentWindow: appWindows.first!)
        }

        return (streamConfig, contentFilter)
    }

    private func startStream(
        configuration: SCStreamConfiguration,
        filter: SCContentFilter
    ) async throws -> SCStream {
        // Create stream
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        // Start stream
        try await stream.startCapture()

        return stream
    }

    private func createVideoWriter(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int
    ) async throws -> AVAssetWriter {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 5, // 5 Mbps per 1080p
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate
            ]
        ]

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        writerInput.expectsMediaDataInRealTime = true

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return writer
    }

    private func createAudioWriter(outputURL: URL) async throws -> AVAssetWriter {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000,
            AVEncoderBitRateKey: 128000
        ]

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings
        )
        writerInput.expectsMediaDataInRealTime = true

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return writer
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let session = currentSession,
              session.isRecording else {
            return
        }

        guard let formatDescription = sampleBuffer.formatDescription else { return }

        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)

        switch mediaType {
        case kCMMediaType_Video:
            if let videoInput = session.getVideoInput(),
               videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }

        case kCMMediaType_Audio:
            if let audioInput = session.getAudioInput(),
               audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }

        default:
            break
        }
    }

    private func startDurationTimer(for session: RecordingSession) {
        Task {
            while session.isRecording {
                if let startTime = session.startTime {
                    session.updateDuration(Date().timeIntervalSince(startTime))
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
    }
}
