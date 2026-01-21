//
//  CaptureEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import ScreenCaptureKit
import AVFoundation

/// Delegate for handling SCStream events
private class StreamDelegate: NSObject, SCStreamDelegate {
    private let onSampleBuffer: (CMSampleBuffer, SCStreamOutputType) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.onSampleBuffer = onSampleBuffer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        onSampleBuffer(sampleBuffer, type)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ERROR] Stream stopped with error: \(error.localizedDescription)")
    }
}

/// Custom SCStreamOutput for handling samples
private class CaptureStreamOutput: NSObject, SCStreamOutput {
    private let onSample: (CMSampleBuffer, SCStreamOutputType) -> Void

    init(onSample: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.onSample = onSample
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        onSample(sampleBuffer, type)
    }
}

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

    private var currentSession: RecordingSession?

    private let sourceSelector = SourceSelector.shared
    private let permissionManager = PermissionManager.shared
    
    private var streamDelegate: StreamDelegate?
    private var videoStreamOutput: CaptureStreamOutput?
    private var audioStreamOutput: CaptureStreamOutput?
    
    // Debug counters
    private var videoFrameCount = 0
    private var audioFrameCount = 0

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

        let (videoWriter, pixelBufferAdaptor) = try await createVideoWriter(
            outputURL: screenVideoURL,
            width: config.display?.width ?? 1920,
            height: config.display?.height ?? 1080,
            frameRate: config.frameRate
        )

        session.setVideoWriter(videoWriter, input: videoWriter.inputs.first!, adaptor: pixelBufferAdaptor)

        if config.captureSystemAudio, let audioURL = systemAudioURL {
            let audioWriter = try await createAudioWriter(outputURL: audioURL)
            session.setAudioWriter(audioWriter, input: audioWriter.inputs.first!)
        }

        // Create and start stream
        let stream = try await startStream(configuration: streamConfig, filter: filter)
        session.setStream(stream)

        // Start recording
        session.markStarted(at: Date())
        
        // Reset frame counters
        videoFrameCount = 0
        audioFrameCount = 0
        print("[DEBUG] Frame counters reset")

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

        print("[DEBUG] Stopping stream...")
        // Stop stream
        if let stream = session.getStream() {
            try? await stream.stopCapture()
        }
        print("[DEBUG] Stream stopped")

        print("[DEBUG] Finalizing video writer...")
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
            print("[DEBUG] Video writer status: \(videoWriter.status.rawValue)")
            if let error = videoWriter.error {
                print("[ERROR] Video writer error: \(error.localizedDescription)")
            }
        } else if let videoWriter = session.getVideoWriter() {
            print("[DEBUG] Video writer already finalized with status: \(videoWriter.status.rawValue)")
        }

        print("[DEBUG] Finalizing audio writer...")
        if let audioWriter = session.getAudioWriter(), audioWriter.status == .writing {
            await audioWriter.finishWriting()
            print("[DEBUG] Audio writer status: \(audioWriter.status.rawValue)")
            if let error = audioWriter.error {
                print("[ERROR] Audio writer error: \(error.localizedDescription)")
            }
        } else if let audioWriter = session.getAudioWriter() {
            print("[DEBUG] Audio writer already finalized with status: \(audioWriter.status.rawValue)")
        }
        
        // Print frame statistics
        print("[DEBUG] Total video frames: \(videoFrameCount)")
        print("[DEBUG] Total audio frames: \(audioFrameCount)")

        // Get output paths from session (these are the real paths where files were created)
        guard let screenVideoPath = session.getVideoOutputURL() else {
            throw CaptureError.recordingNotStarted
        }

        print("[DEBUG] Video output path: \(screenVideoPath.path)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: screenVideoPath.path)
        print("[DEBUG] Video file exists: \(fileExists)")
        
        if fileExists {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: screenVideoPath.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    print("[DEBUG] Video file size: \(fileSize.int64Value) bytes")
                }
            } catch {
                print("[ERROR] Failed to get file attributes: \(error)")
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
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            print("[DEBUG] Available SCDisplay count: \(shareableContent.displays.count)")
            for (index, display) in shareableContent.displays.enumerated() {
                print("[DEBUG] SCDisplay[\(index)]: id=\(display.displayID), width=\(display.width), height=\(display.height)")
            }

            guard let scDisplay: SCDisplay = {
                if let targetID = config.display?.id {
                    print("[DEBUG] Looking for display with config id: \(targetID)")
                    if let cgTargetID = UInt32(targetID) {
                        print("[DEBUG] Converted to CGDisplayID: \(cgTargetID)")
                        return shareableContent.displays.first(where: { $0.displayID == cgTargetID })
                    } else {
                        print("[DEBUG] Failed to convert ID to UInt32")
                    }
                }
                print("[DEBUG] Using first available display as fallback")
                return shareableContent.displays.first
            }() else {
                throw CaptureError.noSourceSelected
            }

            print("[DEBUG] Selected SCDisplay: id=\(scDisplay.displayID)")
            contentFilter = SCContentFilter(display: scDisplay, excludingWindows: [])

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
        print("[DEBUG] Creating SCStream...")

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        print("[DEBUG] SCStream created successfully")

        // Create a queue for sample handling
        let sampleQueue = DispatchQueue(label: "com.cameraman.samplequeue")

        // Add video stream output
        let videoOutput = CaptureStreamOutput { [weak self] sampleBuffer, _ in
            Task { [weak self] in
                guard let self else { return }
                await self.handleSampleBuffer(sampleBuffer)
            }
        }
        
        // Retain output to prevent deallocation
        self.videoStreamOutput = videoOutput
        
        try stream.addStreamOutput(videoOutput, type: .screen, sampleHandlerQueue: sampleQueue)
        print("[DEBUG] Added video stream output")
        
        // Add audio stream output if enabled
        if configuration.capturesAudio {
            let audioOutput = CaptureStreamOutput { [weak self] sampleBuffer, _ in
                Task { [weak self] in
                    guard let self else { return }
                    await self.handleSampleBuffer(sampleBuffer)
                }
            }
            
            // Retain audio output to prevent deallocation
            self.audioStreamOutput = audioOutput
            
            try stream.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: sampleQueue)
            print("[DEBUG] Added audio stream output")
        }

        print("[DEBUG] Starting capture...")
        try await stream.startCapture()
        print("[DEBUG] Capture started successfully")

        return stream
    }

    private func createVideoWriter(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int
    ) async throws -> (writer: AVAssetWriter, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Remove existing file if present (AVAssetWriter fails if file exists)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 5,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate
            ]
        ]

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        writerInput.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for SCStream's CVPixelBuffer output
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        }

        guard writer.startWriting() else {
            print("[ERROR] Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
            throw CaptureError.failedToCreateAssetWriter(underlying: writer.error ?? NSError(domain: "CaptureEngine", code: -1))
        }
        
        print("[DEBUG] Video writer started successfully at: \(outputURL.path)")

        return (writer, adaptor)
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
        // Don't start session here - will start with first audio frame's timestamp
        // to match SCStream's absolute timestamps

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
            videoFrameCount += 1
            if videoFrameCount % 60 == 1 { // Log every 60 frames (~1 second at 60fps)
                print("[DEBUG] Video frames received: \(videoFrameCount)")
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                if videoFrameCount < 10 {
                    print("[WARN] No pixel buffer in video sample at frame \(videoFrameCount)")
                }
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if session.getFirstVideoTimestamp() == nil {
                session.setFirstVideoTimestamp(presentationTime)
                if let writer = session.getVideoWriter() {
                    writer.startSession(atSourceTime: .zero)
                    print("[DEBUG] Video session started")
                }
            }

            guard let firstTimestamp = session.getFirstVideoTimestamp() else { return }
            let relativeTime = CMTimeSubtract(presentationTime, firstTimestamp)

            if let adaptor = session.getPixelBufferAdaptor(),
               adaptor.assetWriterInput.isReadyForMoreMediaData {
                let success = adaptor.append(pixelBuffer, withPresentationTime: relativeTime)
                if !success, let writer = session.getVideoWriter() {
                    print("[ERROR] Failed to append video frame \(videoFrameCount). Writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
                }
            } else {
                if videoFrameCount < 10 {
                    print("[WARN] Video input not ready for more data at frame \(videoFrameCount)")
                }
            }

        case kCMMediaType_Audio:
            audioFrameCount += 1
            if audioFrameCount % 100 == 1 {
                print("[DEBUG] Audio frames received: \(audioFrameCount)")
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if session.getFirstAudioTimestamp() == nil {
                session.setFirstAudioTimestamp(presentationTime)
                if let writer = session.getAudioWriter() {
                    writer.startSession(atSourceTime: .zero)
                    print("[DEBUG] Audio session started")
                }
            }

            guard let firstAudioTimestamp = session.getFirstAudioTimestamp() else { return }

            let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
            var neededTimingEntryCount = 0
            var timingInfos = Array(
                repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
                count: sampleCount
            )
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: sampleCount,
                arrayToFill: &timingInfos,
                entriesNeededOut: &neededTimingEntryCount
            )
            if neededTimingEntryCount > 0 {
                for i in 0..<neededTimingEntryCount {
                    timingInfos[i].presentationTimeStamp = CMTimeSubtract(timingInfos[i].presentationTimeStamp, firstAudioTimestamp)
                    if timingInfos[i].decodeTimeStamp.isValid {
                        timingInfos[i].decodeTimeStamp = CMTimeSubtract(timingInfos[i].decodeTimeStamp, firstAudioTimestamp)
                    }
                }
            }

            var adjustedSampleBuffer: CMSampleBuffer?
            let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: neededTimingEntryCount,
                sampleTimingArray: timingInfos,
                sampleBufferOut: &adjustedSampleBuffer
            )
            guard copyStatus == noErr, let adjustedSampleBuffer else {
                if audioFrameCount < 10 {
                    print("[ERROR] Failed to retime audio sample buffer: \(copyStatus)")
                }
                return
            }

            if let audioInput = session.getAudioInput(),
               audioInput.isReadyForMoreMediaData {
                let success = audioInput.append(adjustedSampleBuffer)
                if !success, let writer = session.getAudioWriter() {
                    print("[ERROR] Failed to append audio frame \(audioFrameCount). Writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
                }
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
