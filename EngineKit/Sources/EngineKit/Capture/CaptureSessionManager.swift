//
//  CaptureSessionManager.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import ScreenCaptureKit
import AVFoundation

extension CaptureEngine {
    func validateConfiguration(_ config: CaptureConfiguration) throws {
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

    /// Compute output pixel dimensions for the given configuration.
    func outputDimensions(for config: CaptureConfiguration) -> (width: Int, height: Int) {
        let nativeWidth: Int
        let nativeHeight: Int

        if let rect = config.captureRect {
            // Area selection: convert from points to pixels using display scale
            let scale = config.display?.backingScaleFactor ?? 1.0
            nativeWidth = Int(rect.width * scale)
            nativeHeight = Int(rect.height * scale)
        } else {
            switch config.sourceType {
            case .display:
                nativeWidth = config.display?.width ?? 1920
                nativeHeight = config.display?.height ?? 1080
            case .window:
                nativeWidth = config.window?.width ?? 1920
                nativeHeight = config.window?.height ?? 1080
            case .application:
                nativeWidth = 1920
                nativeHeight = 1080
            }
        }

        return config.quality.outputSize(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
    }

    func setupStreamConfiguration(
        _ config: CaptureConfiguration
    ) async throws -> (SCStreamConfiguration, SCContentFilter) {
        let streamConfig = SCStreamConfiguration()

        let (width, height) = outputDimensions(for: config)
        streamConfig.width = width
        streamConfig.height = height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.pixelFormat = config.pixelFormat
        streamConfig.capturesAudio = config.captureSystemAudio

        // Apply capture area if set (top-left origin, in display points)
        if let rect = config.captureRect {
            streamConfig.sourceRect = rect
        }

        // Setup content filter
        let contentFilter: SCContentFilter

        switch config.sourceType {
        case .display:
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            logger.debug("Available SCDisplay count: \(shareableContent.displays.count)")
            for (index, display) in shareableContent.displays.enumerated() {
                logger.debug("SCDisplay[\(index)]: id=\(display.displayID), width=\(display.width), height=\(display.height)")
            }

            guard let scDisplay: SCDisplay = {
                if let targetID = config.display?.id {
                    logger.debug("Looking for display with config id: \(targetID)")
                    if let cgTargetID = UInt32(targetID) {
                        logger.debug("Converted to CGDisplayID: \(cgTargetID)")
                        return shareableContent.displays.first(where: { $0.displayID == cgTargetID })
                    } else {
                        logger.debug("Failed to convert ID to UInt32")
                    }
                }
                logger.debug("Using first available display as fallback")
                return shareableContent.displays.first
            }() else {
                throw CaptureError.noSourceSelected
            }

            logger.debug("Selected SCDisplay: id=\(scDisplay.displayID)")
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

            guard let firstWindow = appWindows.first else {
                throw CaptureError.noSourceSelected
            }
            contentFilter = SCContentFilter(desktopIndependentWindow: firstWindow)
        }

        return (streamConfig, contentFilter)
    }

    func startStream(
        configuration: SCStreamConfiguration,
        filter: SCContentFilter
    ) async throws -> SCStream {
        logger.debug("Creating SCStream...")

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        logger.debug("SCStream created successfully")

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
        logger.debug("Added video stream output")

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
            logger.debug("Added audio stream output")
        }

        logger.debug("Starting capture...")
        try await stream.startCapture()
        logger.debug("Capture started successfully")

        return stream
    }

    func createVideoWriter(
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
            logger.error("Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")")
            throw CaptureError.failedToCreateAssetWriter(underlying: writer.error ?? NSError(domain: "CaptureEngine", code: -1))
        }

        logger.debug("Video writer started successfully at: \(outputURL.path)")

        return (writer, adaptor)
    }

    func createAudioWriter(outputURL: URL) async throws -> AVAssetWriter {
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

    func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
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
                logger.debug("Video frames received: \(self.videoFrameCount)")
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                if videoFrameCount < 10 {
                    logger.warning("No pixel buffer in video sample at frame \(self.videoFrameCount)")
                }
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if session.getFirstVideoTimestamp() == nil {
                session.setFirstVideoTimestamp(presentationTime)
                if let writer = session.getVideoWriter() {
                    writer.startSession(atSourceTime: .zero)
                    logger.debug("Video session started")
                }
            }

            guard let firstTimestamp = session.getFirstVideoTimestamp() else { return }
            let relativeTime = CMTimeSubtract(presentationTime, firstTimestamp)

            if let adaptor = session.getPixelBufferAdaptor(),
               adaptor.assetWriterInput.isReadyForMoreMediaData {
                let success = adaptor.append(pixelBuffer, withPresentationTime: relativeTime)
                if !success, let writer = session.getVideoWriter() {
                    logger.error("Failed to append video frame \(self.videoFrameCount). Writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
                }
            } else {
                if videoFrameCount < 10 {
                    logger.warning("Video input not ready for more data at frame \(self.videoFrameCount)")
                }
            }

        case kCMMediaType_Audio:
            audioFrameCount += 1
            if audioFrameCount % 100 == 1 {
                logger.debug("Audio frames received: \(self.audioFrameCount)")
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if session.getFirstAudioTimestamp() == nil {
                session.setFirstAudioTimestamp(presentationTime)
                if let writer = session.getAudioWriter() {
                    writer.startSession(atSourceTime: .zero)
                    logger.debug("Audio session started")
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
                    logger.error("Failed to retime audio sample buffer: \(copyStatus)")
                }
                return
            }

            if let audioInput = session.getAudioInput(),
               audioInput.isReadyForMoreMediaData {
                let success = audioInput.append(adjustedSampleBuffer)
                if !success, let writer = session.getAudioWriter() {
                    logger.error("Failed to append audio frame \(self.audioFrameCount). Writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
                }
            }

        default:
            break
        }

    }

    func startDurationTimer(for session: RecordingSession) {
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
