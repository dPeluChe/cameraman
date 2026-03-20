//
//  CameraEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// CameraEngine manages camera capture as a separate track
public actor CameraEngine {
    // MARK: - Properties

    /// Shared instance
    public static let shared = CameraEngine()

    private var currentSession: RecordingSession?
    private let permissionManager = PermissionManager.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// List all available camera devices
    /// - Returns: Array of CameraDevice
    public func listAvailableCameras() -> [CameraDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        return discoverySession.devices.map { device in
            CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                localizedName: device.localizedName,
                position: device.position
            )
        }
    }

    /// Check if camera is available on this device
    /// - Returns: true if camera hardware is available
    public func isCameraAvailable() -> Bool {
        return !listAvailableCameras().isEmpty
    }

    /// Start a camera recording session with the given configuration
    /// - Parameters:
    ///   - config: Camera configuration
    ///   - outputURL: URL for output file
    /// - Returns: RecordingSession
    public func startRecording(
        config: CameraConfiguration,
        outputURL: URL
    ) async throws -> RecordingSession {
        // Check if recording is already in progress
        guard currentSession == nil else {
            throw CameraError.recordingAlreadyInProgress
        }

        // Check permissions
        let permission = await permissionManager.checkCameraPermission()
        guard permission == .authorized else {
            throw CameraError.permissionDenied
        }

        // Check camera availability
        guard isCameraAvailable() else {
            throw CameraError.cameraNotAvailable
        }

        // Get camera device
        let device: AVCaptureDevice
        if let deviceID = config.deviceID {
            guard let foundDevice = AVCaptureDevice(uniqueID: deviceID) else {
                throw CameraError.deviceNotFound
            }
            device = foundDevice
        } else {
            // Use default front-facing camera
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            guard let defaultDevice = discoverySession.devices.first else {
                throw CameraError.cameraNotAvailable
            }
            device = defaultDevice
        }

        // Create session
        let session = RecordingSession()
        currentSession = session

        // Setup capture session
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        // Setup device input
        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(deviceInput) else {
            throw CameraError.failedToStartSession(underlying: CameraError.invalidConfiguration)
        }
        captureSession.addInput(deviceInput)

        // Configure device for specific frame rate
        try configureDevice(device, forFrameRate: config.frameRate)

        // Create output directory if needed
        let outputDirectory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Setup asset writer
        let dimensions = config.resolutionPreset.dimensions
        let assetWriter = try createVideoWriter(
            outputURL: outputURL,
            width: dimensions.width,
            height: dimensions.height,
            frameRate: config.frameRate,
            codec: config.codec.codecType
        )

        let assetWriterInput = assetWriter.inputs.first!
        session.setAssetWriter(assetWriter, input: assetWriterInput)
        session.setOutputURL(outputURL)

        // Setup video data output for pixel buffer delivery
        let videoDataOutput = AVCaptureVideoDataOutput()

        // IMPORTANT: AVCaptureVideoDataOutput does NOT retain its delegate.
        // We must keep a strong reference alive for the duration of the session.
        let sampleDelegate = CameraSampleBufferDelegate(
            assetWriterInput: assetWriterInput,
            sessionStartTime: Date(),
            syncOffsetMs: config.syncOffsetMs
        )
        session.setSampleBufferDelegate(sampleDelegate)

        videoDataOutput.setSampleBufferDelegate(
            sampleDelegate,
            queue: DispatchQueue(label: "com.enginekit.camera.samplebuffer")
        )
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = false

        guard captureSession.canAddOutput(videoDataOutput) else {
            throw CameraError.failedToStartSession(underlying: CameraError.invalidConfiguration)
        }
        captureSession.addOutput(videoDataOutput)

        session.setCaptureSession(captureSession)

        // Start session
        captureSession.startRunning()

        // Start asset writer
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)

        // Mark session as started
        session.markStarted(at: Date())

        // Start timer for duration tracking
        startDurationTimer(for: session)

        return session
    }

    /// Stop the current camera recording session
    /// - Parameter session: The session to stop
    /// - Returns: RecordingResult with path to recorded file
    public func stopRecording(session: RecordingSession, config: CameraConfiguration) async throws -> RecordingResult {
        guard currentSession?.id == session.id else {
            throw CameraError.recordingNotStarted
        }

        guard session.isRecording else {
            throw CameraError.recordingNotStarted
        }

        session.markStopped()

        // Stop capture session
        if let captureSession = session.getCaptureSession() {
            captureSession.stopRunning()
        }

        // Finalize writer
        if let assetWriterInput = session.getAssetWriterInput() {
            assetWriterInput.markAsFinished()
        }

        if let assetWriter = session.getAssetWriter(), assetWriter.status == .writing {
            await assetWriter.finishWriting()
        }

        // Get output path
        guard let cameraVideoPath = session.getOutputURL() else {
            throw CameraError.recordingNotStarted
        }

        let result = RecordingResult(
            session: session,
            cameraVideoPath: cameraVideoPath,
            duration: session.duration,
            syncOffsetMs: config.syncOffsetMs,
            startTime: session.startTime ?? Date(),
            endTime: Date()
        )

        currentSession = nil

        return result
    }

    // MARK: - Private Helpers

    private func configureDevice(_ device: AVCaptureDevice, forFrameRate frameRate: Int) throws {
        try device.lockForConfiguration()

        // Find the best format for the desired frame rate
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRateRange: AVFrameRateRange?

        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Double(frameRate) {
                    if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                        bestFormat = format
                        bestFrameRateRange = range
                    }
                }
            }
        }

        // Set format if found
        if let format = bestFormat,
           bestFrameRateRange != nil {
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        }

        device.unlockForConfiguration()
    }

    private func createVideoWriter(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        codec: AVVideoCodecType
    ) throws -> AVAssetWriter {
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

        var compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey: width * height * 3, // 3 Mbps for 720p, 6 Mbps for 1080p
            AVVideoExpectedSourceFrameRateKey: frameRate
        ]

        // Set profile level based on codec
        if codec == .h264 {
            compressionSettings[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionSettings
        ]

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        writerInput.expectsMediaDataInRealTime = true

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        }

        return writer
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

// MARK: - Camera Sample Buffer Delegate

private class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let assetWriterInput: AVAssetWriterInput
    private let sessionStartTime: Date
    private let syncOffsetMs: Double

    init(assetWriterInput: AVAssetWriterInput, sessionStartTime: Date, syncOffsetMs: Double) {
        self.assetWriterInput = assetWriterInput
        self.sessionStartTime = sessionStartTime
        self.syncOffsetMs = syncOffsetMs
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard assetWriterInput.isReadyForMoreMediaData else {
            return
        }

        // Apply sync offset to timestamp
        var timingInfo = CMSampleTimingInfo()
        var newSampleBuffer: CMSampleBuffer?

        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)

        // Calculate adjusted timestamp with sync offset
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let adjustedElapsed = elapsed + (syncOffsetMs / 1000.0)

        timingInfo.presentationTimeStamp = CMTime(
            seconds: adjustedElapsed,
            preferredTimescale: 600
        )
        timingInfo.decodeTimeStamp = .invalid

        // Get the image buffer and format description
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            // Fallback to original buffer if adjustment fails
            assetWriterInput.append(sampleBuffer)
            return
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            // Fallback to original buffer if adjustment fails
            assetWriterInput.append(sampleBuffer)
            return
        }

        // Create new sample buffer with adjusted timing
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )

        if status == noErr, let adjustedBuffer = newSampleBuffer {
            assetWriterInput.append(adjustedBuffer)
        } else {
            // Fallback to original buffer if adjustment fails
            assetWriterInput.append(sampleBuffer)
        }
    }
}
