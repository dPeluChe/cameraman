//
//  ProxyGenerator.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

/// Generator for low-resolution proxy videos for smooth preview
public actor ProxyGenerator {
    /// Progress handler for proxy generation
    public typealias ProgressHandler = @Sendable (Double) -> Void

    /// Cancellation token for async operations
    private class CancellationToken: @unchecked Sendable {
        private var _isCancelled: Bool = false
        private let lock = NSLock()

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            _isCancelled = true
        }
    }

    private var currentCancellationToken: CancellationToken?

    // MARK: - Public API

    /// Generate proxy for a video file
    /// - Parameters:
    ///   - sourcePath: Path to source video file
    ///   - outputPath: Path where proxy should be saved
    ///   - configuration: Proxy generation configuration
    ///   - progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: ProxyResult with metadata
    /// - Throws: ProxyError if generation fails
    public func generateProxy(
        from sourcePath: String,
        to outputPath: String,
        configuration: Configuration = .default,
        progress: ProgressHandler? = nil
    ) async throws -> ProxyResult {
        // Check if source file exists
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw ProxyError.sourceFileNotFound(sourcePath)
        }

        // Get source file size
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: sourcePath)
        let sourceSizeBytes = sourceAttributes[.size] as? UInt64 ?? 0

        // Check disk space
        let estimatedProxySize = estimateProxySize(sourceSizeBytes: sourceSizeBytes, configuration: configuration)
        guard try checkDiskSpace(for: estimatedProxySize, at: outputPath) else {
            let availableSpace = getAvailableDiskSpace(at: outputPath)
            throw ProxyError.insufficientDiskSpace(required: estimatedProxySize, available: availableSpace)
        }

        // Create cancellation token for this operation
        let cancellationToken = CancellationToken()
        self.currentCancellationToken = cancellationToken

        // Create asset from source file
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let asset = AVAsset(url: sourceURL)

        // Load asset properties
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = tracks.first else {
            throw ProxyError.failedToCreateAsset("No video track found in source file")
        }

        // Get source video dimensions
        let naturalSize = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Calculate output dimensions (preserve aspect ratio if enabled)
        let outputSize = calculateOutputSize(
            sourceSize: naturalSize,
            config: configuration
        )

        // Create asset reader
        let assetReader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        assetReader.add(readerOutput)

        guard assetReader.startReading() else {
            throw ProxyError.failedToCreateReader("Failed to start reading from source")
        }

        // Create asset writer
        let outputURL = URL(fileURLWithPath: outputPath)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.outputFormat)

        // Video output settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: configuration.codec,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.targetBitrate * 1_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: configuration.frameRate,
                AVVideoMaxKeyFrameIntervalKey: configuration.frameRate * 2 // Keyframe every 2 seconds
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        // Add adaptor for pixel buffer conversion
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height
            ]
        )

        writer.add(writerInput)

        guard writer.startWriting() else {
            throw ProxyError.failedToStartWriting("Failed to start writing to output")
        }

        writer.startSession(atSourceTime: .zero)

        // Read and write frames
        var frameCount = 0
        let frameRate = Int(configuration.frameRate)
        let totalFramesEstimate = Int(duration * Double(frameRate))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        // Calculate pixel buffer pool attributes for resizing
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        // Process frames
        var lastSampleTime: CMTime?
        var currentFrameTime = CMTime.zero

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            // Check for cancellation
            if cancellationToken.isCancelled {
                assetReader.cancelReading()
                writer.cancelWriting()
                throw ProxyError.cancelled
            }

            // Get sample time and size
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let sourceSize = CMSampleBufferGetImageBuffer(sampleBuffer).map { buffer in
                CoreFoundation.CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            }

            // Skip frames to match target frame rate (simple frame dropping)
            if let lastTime = lastSampleTime {
                let nextFrameTime = CMTimeAdd(lastTime, frameDuration)
                if sampleTime < nextFrameTime {
                    // Skip this frame
                    continue
                }
            }

            // Get image buffer from sample
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            // Create resized pixel buffer
            var resizedBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(outputSize.width),
                Int(outputSize.height),
                kCVPixelFormatType_32BGRA,
                pixelBufferAttributes as CFDictionary,
                &resizedBuffer
            )

            guard status == kCVReturnSuccess, let outputBuffer = resizedBuffer else {
                continue
            }

            // Resize the image using Core Graphics
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(outputBuffer, [])

            defer {
                CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            }

            guard let sourceContext = createCGContext(from: imageBuffer),
                  let destContext = createCGContext(from: outputBuffer) else {
                continue
            }

            // Create image from source buffer
            guard let sourceImage = sourceContext.makeImage() else {
                continue
            }

            // Calculate draw rect (aspect ratio aware)
            let drawRect = calculateDrawRect(
                sourceSize: sourceSize ?? CoreFoundation.CGSize(
                    width: CVPixelBufferGetWidth(imageBuffer),
                    height: CVPixelBufferGetHeight(imageBuffer)
                ),
                destSize: CoreFoundation.CGSize(width: outputSize.width, height: outputSize.height),
                preserveAspectRatio: configuration.preserveAspectRatio
            )

            // Draw resized image
            destContext.draw(sourceImage, in: drawRect)

            // Append buffer to writer
            while !writerInput.isReadyForMoreMediaData {
                // Small delay to avoid busy waiting
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }

            adaptor.append(outputBuffer, withPresentationTime: currentFrameTime)

            // Update timing
            lastSampleTime = sampleTime
            currentFrameTime = CMTimeAdd(currentFrameTime, frameDuration)
            frameCount += 1

            // Report progress
            if totalFramesEstimate > 0 {
                let progressValue = Double(frameCount) / Double(totalFramesEstimate)
                progress?(min(progressValue, 1.0))
            }
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        // Check for errors
        if writer.status == .failed {
            throw ProxyError.failedToFinishWriting(writer.error?.localizedDescription ?? "Unknown error")
        }

        // Get output file size
        let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputPath)
        let outputSizeBytes = outputAttributes[.size] as? UInt64 ?? 0

        return ProxyResult(
            proxyPath: outputPath,
            sourcePath: sourcePath,
            duration: duration,
            sizeBytes: outputSizeBytes,
            originalSizeBytes: sourceSizeBytes
        )
    }

    /// Generate proxies for all video tracks in a project
    /// - Parameters:
    ///   - project: Project to generate proxies for
    ///   - projectDirectory: Project's directory path
    ///   - configuration: Proxy generation configuration
    ///   - progress: Optional progress handler (0.0 to 1.0)
    /// - Returns: Dictionary of track type to ProxyResult
    /// - Throws: ProxyError if generation fails
    public func generateProjectProxies(
        for project: Project,
        projectDirectory: String,
        configuration: Configuration = .default,
        progress: ProgressHandler? = nil
    ) async throws -> [String: ProxyResult] {
        var results: [String: ProxyResult] = [String: ProxyResult]()
        let proxiesDirectory = (projectDirectory as NSString).appendingPathComponent("proxies")

        // Create proxies directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: proxiesDirectory) {
            try FileManager.default.createDirectory(
                atPath: proxiesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Determine which tracks need proxies
        var tracksToProcess: [(type: String, sourcePath: String, outputPath: String)] = []

        guard let sources = project.primarySources else {
            // No sources to process
            return [:]
        }

        // Screen track
        let screenProxyPath = (proxiesDirectory as NSString).appendingPathComponent("screen_proxy.mov")
        tracksToProcess.append((
            type: "screen",
            sourcePath: (projectDirectory as NSString).appendingPathComponent(sources.screen.path),
            outputPath: screenProxyPath
        ))

        // Camera track (if present)
        if let camera = sources.camera {
            let cameraProxyPath = (proxiesDirectory as NSString).appendingPathComponent("camera_proxy.mov")
            tracksToProcess.append((
                type: "camera",
                sourcePath: (projectDirectory as NSString).appendingPathComponent(camera.path),
                outputPath: cameraProxyPath
            ))
        }

        // Generate proxies for each track
        let totalTracks = tracksToProcess.count
        for (index, track) in tracksToProcess.enumerated() {
            // Calculate progress range for this track
            let progressStart = Double(index) / Double(totalTracks)
            let progressEnd = Double(index + 1) / Double(totalTracks)

            let trackProgress: ProgressHandler = { trackProgress in
                let overallProgress = progressStart + (trackProgress * (progressEnd - progressStart))
                progress?(overallProgress)
            }

            // Check if proxy already exists and is up to date
            if FileManager.default.fileExists(atPath: track.outputPath) {
                let sourceAttributes = try FileManager.default.attributesOfItem(atPath: track.sourcePath)
                let proxyAttributes = try FileManager.default.attributesOfItem(atPath: track.outputPath)

                let sourceModDate = sourceAttributes[.modificationDate] as? Date ?? Date.distantPast
                let proxyModDate = proxyAttributes[.modificationDate] as? Date ?? Date.distantPast

                if proxyModDate > sourceModDate {
                    // Proxy is up to date, skip generation
                    let sourceSizeBytes = sourceAttributes[.size] as? UInt64 ?? 0
                    let proxySizeBytes = proxyAttributes[.size] as? UInt64 ?? 0

                    results[track.type] = ProxyResult(
                        proxyPath: track.outputPath,
                        sourcePath: track.sourcePath,
                        duration: 0, // Duration will be loaded by PreviewEngine
                        sizeBytes: proxySizeBytes,
                        originalSizeBytes: sourceSizeBytes
                    )
                    continue
                }
            }

            // Generate proxy
            let result = try await generateProxy(
                from: track.sourcePath,
                to: track.outputPath,
                configuration: configuration,
                progress: trackProgress
            )

            results[track.type] = result
        }

        return results
    }

    /// Cancel the current proxy generation operation
    public func cancel() {
        currentCancellationToken?.cancel()
    }

    // MARK: - Helper Methods

    /// Estimate proxy file size based on source size and configuration
    private func estimateProxySize(sourceSizeBytes: UInt64, configuration: Configuration) -> UInt64 {
        // Rough estimation based on resolution and bitrate
        let sourcePixels = 1920 * 1080 // Assume 1080p source
        let proxyPixels = configuration.width * configuration.height
        let resolutionRatio = Double(proxyPixels) / Double(sourcePixels)

        // Bitrate ratio (assuming source is ~20 Mbps)
        let sourceBitrate = 20.0 // Mbps
        let proxyBitrate = Double(configuration.targetBitrate)
        let bitrateRatio = proxyBitrate / sourceBitrate

        let estimatedRatio = resolutionRatio * bitrateRatio
        return UInt64(Double(sourceSizeBytes) * estimatedRatio * 1.2) // 20% buffer
    }

    /// Check if there's enough disk space
    private func checkDiskSpace(for sizeBytes: UInt64, at path: String) throws -> Bool {
        let availableSpace = getAvailableDiskSpace(at: path)
        return availableSpace >= sizeBytes
    }

    /// Get available disk space at a given path
    private func getAvailableDiskSpace(at path: String) -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.systemFreeSize] as? UInt64 ?? 0
        } catch {
            return 0
        }
    }

    /// Calculate output size based on source and configuration
    private func calculateOutputSize(
        sourceSize: CoreFoundation.CGSize,
        config: Configuration
    ) -> CoreFoundation.CGSize {
        if config.preserveAspectRatio {
            let sourceAspect = sourceSize.width / sourceSize.height
            let configAspect = Double(config.width) / Double(config.height)

            if sourceAspect > configAspect {
                // Source is wider, fit width
                let height = Double(config.width) / sourceAspect
                return CoreFoundation.CGSize(width: config.width, height: Int(height))
            } else {
                // Source is taller, fit height
                let width = Double(config.height) * sourceAspect
                return CoreFoundation.CGSize(width: Int(width), height: config.height)
            }
        } else {
            return CoreFoundation.CGSize(width: config.width, height: config.height)
        }
    }

    /// Calculate draw rect for aspect-ratio-preserving resize
    private func calculateDrawRect(
        sourceSize: CoreFoundation.CGSize,
        destSize: CoreFoundation.CGSize,
        preserveAspectRatio: Bool
    ) -> CoreFoundation.CGRect {
        if preserveAspectRatio {
            let sourceAspect = sourceSize.width / sourceSize.height
            let destAspect = destSize.width / destSize.height

            if sourceAspect > destAspect {
                // Source is wider, fit width
                let height = destSize.width / sourceAspect
                let y = (destSize.height - height) / 2
                return CoreFoundation.CGRect(x: 0, y: y, width: destSize.width, height: height)
            } else {
                // Source is taller, fit height
                let width = destSize.height * sourceAspect
                let x = (destSize.width - width) / 2
                return CoreFoundation.CGRect(x: x, y: 0, width: width, height: destSize.height)
            }
        } else {
            return CoreFoundation.CGRect(x: 0, y: 0, width: destSize.width, height: destSize.height)
        }
    }

    /// Create CGContext from CVPixelBuffer
    private func createCGContext(from pixelBuffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        return context
    }

    /// Check if proxy file exists for a given source
    /// - Parameters:
    ///   - sourcePath: Path to source file
    ///   - projectDirectory: Project's directory path
    /// - Returns: Path to proxy file if it exists, nil otherwise
    public func getProxyPath(for sourcePath: String, projectDirectory: String) -> String? {
        let proxiesDirectory = (projectDirectory as NSString).appendingPathComponent("proxies")
        let fileName = ((sourcePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let proxyFileName = "\(fileName)_proxy.mov"
        let proxyPath = (proxiesDirectory as NSString).appendingPathComponent(proxyFileName)

        return FileManager.default.fileExists(atPath: proxyPath) ? proxyPath : nil
    }
}
