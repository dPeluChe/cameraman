//
//  LocalAIProvider.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

/// Local AI provider implementation using Vision framework and CoreImage
///
/// This provider implements experimental AI features entirely on-device:
/// - Background generation: Uses CoreImage filters to generate procedural backgrounds
/// - Style transfer: Uses CoreImage filters for artistic effects
/// - Camera background replacement: Uses Vision for person segmentation (experimental)
///
/// Note: These are experimental "Labs" features and may not match the quality of cloud AI.
public actor LocalAIProvider: AIProvider {
    /// Context for image processing
    let ciContext: CIContext

    /// File manager for asset operations
    let fileManager = FileManager.default

    /// Initialize LocalAIProvider
    public init() {
        // Create CIContext for image processing
        self.ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .useSoftwareRenderer: false // Use GPU when available
        ])
    }

    // MARK: - Background Generation

    /// Generate a background image using procedural generation
    ///
    /// This implementation uses CoreImage filters to create abstract backgrounds
    /// based on the prompt. This is a simplified implementation compared to
    /// generative AI models (DALL-E, Midjourney, etc.), but works entirely offline.
    ///
    /// - Parameters:
    ///   - prompt: Text description (keywords are extracted)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - style: Background style preset
    /// - Returns: Generated image as AssetRef
    public func generateBackground(
        prompt: String,
        width: Int,
        height: Int,
        style: BackgroundStyle
    ) async throws -> AssetRef {
        // Extract keywords from prompt for procedural generation
        let keywords = extractKeywords(from: prompt)

        // Generate image using CoreImage
        let image = try await generateProceduralImage(
            keywords: keywords,
            width: width,
            height: height,
            style: style
        )

        // Convert to PNG data
        guard let imageData = image.pngRepresentation() else {
            throw AIServiceError.generationFailed("Failed to encode image")
        }

        // Generate filename
        let filename = "background_\(UUID().uuidString.prefix(8)).png"

        return AssetRef(
            type: .image,
            filename: filename,
            data: imageData,
            url: nil,
            thumbnail: generateThumbnail(from: imageData),
            metadata: [
                "prompt": prompt,
                "width": String(width),
                "height": String(height),
                "style": style.rawValue
            ]
        )
    }

    // MARK: - Style Transfer

    /// Apply style transfer to video using CoreImage filters
    ///
    /// This implementation uses CoreImage filters for artistic effects.
    /// For true style transfer (neural style transfer), you would need
    /// a CoreML model, which is beyond the scope of this implementation.
    ///
    /// - Parameters:
    ///   - projectId: Project to process
    ///   - style: Style name (maps to CoreImage filters)
    ///   - strength: Effect strength (0.0 - 1.0)
    /// - Returns: Processed video as AssetRef
    public func applyStyleTransfer(
        projectId: ProjectId,
        style: String,
        strength: Double
    ) async throws -> AssetRef {
        // Get project path
        let projectURL = projectURL(for: projectId)
        let screenPath = projectURL.appendingPathComponent("sources/screen.mov")

        guard fileManager.fileExists(atPath: screenPath.path) else {
            throw AIServiceError.generationFailed("Source video not found")
        }

        // Map style names to CoreImage filters
        let filterName = mapStyleToFilter(style)

        // Apply filter to video
        let outputURL = try await applyVideoFilter(
            inputURL: screenPath,
            filterName: filterName,
            strength: strength
        )

        // Read output video data
        let videoData = try Data(contentsOf: outputURL)

        return AssetRef(
            type: .styledVideo,
            filename: outputURL.lastPathComponent,
            data: videoData,
            url: outputURL,
            thumbnail: nil,
            metadata: [
                "style": style,
                "strength": String(strength),
                "filter": filterName
            ]
        )
    }

    // MARK: - Camera Background Replacement

    /// Replace background in camera track using person segmentation
    ///
    /// This implementation uses Vision framework for person segmentation (macOS 11+).
    /// This is experimental and may not work perfectly in all scenarios.
    ///
    /// For production use, consider using:
    /// - CoreML models for better segmentation
    /// - Cloud providers with advanced ML models
    ///
    /// - Parameters:
    ///   - projectId: Project to process
    ///   - background: Background asset to apply
    ///   - edgeSmoothness: Edge smoothing (0.0 - 1.0)
    /// - Returns: Processed camera video as AssetRef
    public func replaceCameraBackground(
        projectId: ProjectId,
        background: AssetRef,
        edgeSmoothness: Double
    ) async throws -> AssetRef {
        // Get project path
        let projectURL = projectURL(for: projectId)
        let cameraPath = projectURL.appendingPathComponent("sources/camera.mov")

        guard fileManager.fileExists(atPath: cameraPath.path) else {
            throw AIServiceError.generationFailed("Camera video not found")
        }

        // Load background image
        let backgroundImage = try loadImage(from: background)

        // Apply background replacement
        let outputURL = try await performBackgroundReplacement(
            inputURL: cameraPath,
            background: backgroundImage,
            edgeSmoothness: edgeSmoothness
        )

        // Read output video data
        let videoData = try Data(contentsOf: outputURL)

        return AssetRef(
            type: .processedCamera,
            filename: outputURL.lastPathComponent,
            data: videoData,
            url: outputURL,
            thumbnail: nil,
            metadata: [
                "background_filename": background.filename,
                "edge_smoothness": String(edgeSmoothness)
            ]
        )
    }

    /// Apply video filter using AVAssetWriter
    private func applyVideoFilter(
        inputURL: URL,
        filterName: String,
        strength: Double
    ) async throws -> URL {
        // Create output URL
        let outputURL = inputURL.deletingLastPathComponent()
            .appendingPathComponent("styled_\(UUID().uuidString.prefix(8)).mov")

        // Load asset
        let asset = AVAsset(url: inputURL)

        // Create reader
        let reader = try AVAssetReader(asset: asset)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first

        guard let videoTrack = videoTrack else {
            throw AIServiceError.generationFailed("No video track found")
        }

        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        reader.add(readerOutput)

        // Create writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: try await videoTrack.load(.naturalSize).width,
                AVVideoHeightKey: try await videoTrack.load(.naturalSize).height
            ]
        )

        // Create adaptor for pixel buffers
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: try await videoTrack.load(.naturalSize).width,
                kCVPixelBufferHeightKey as String: try await videoTrack.load(.naturalSize).height
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        // The AVFoundation reader/writer types aren't Sendable, but in this
        // pipeline they are accessed serially on a dedicated dispatch queue,
        // so the captures are safe. Wrap in @unchecked Sendable to satisfy
        // the compiler.
        let pipeline = UncheckedSendableAVPipeline(
            writerInput: writerInput,
            readerOutput: readerOutput,
            adaptor: adaptor,
            writer: writer,
            reader: reader
        )

        // Apply filter to each frame
        writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video_filter")) {
            while pipeline.writerInput.isReadyForMoreMediaData {
                autoreleasepool {
                    if let sampleBuffer = pipeline.readerOutput.copyNextSampleBuffer() {
                        if let filteredBuffer = self.applyFilterToSampleBuffer(
                            sampleBuffer: sampleBuffer,
                            filterName: filterName,
                            strength: strength
                        ) {
                            pipeline.adaptor.append(filteredBuffer, withPresentationTime: sampleBuffer.presentationTimeStamp)
                        }
                    } else {
                        pipeline.writerInput.markAsFinished()
                        pipeline.writer.finishWriting {
                            pipeline.reader.cancelReading()
                        }
                    }
                }
            }
        }

        // Wait for completion
        await writer.finishWriting()

        return outputURL
    }

    /// Apply CoreImage filter to sample buffer
    private nonisolated func applyFilterToSampleBuffer(
        sampleBuffer: CMSampleBuffer,
        filterName: String,
        strength: Double
    ) -> CVPixelBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        // Use a shared CIContext for this nonisolated method
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        var outputImage = ciImage

        // Apply filter based on name
        if filterName == "CISepiaTone" {
            let filter = CIFilter(name: "CISepiaTone")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(Float(strength), forKey: kCIInputIntensityKey)
            outputImage = filter.outputImage ?? ciImage
        } else if filterName == "CIVignette" {
            let filter = CIFilter(name: "CIVignette")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(Float(strength), forKey: kCIInputIntensityKey)
            filter.setValue(Float(strength * 2.0), forKey: kCIInputRadiusKey)
            outputImage = filter.outputImage ?? ciImage
        } else {
            // Apply photo effect
            if let filter = CIFilter(name: filterName) {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                outputImage = filter.outputImage ?? ciImage
            }
        }

        // Render back to pixel buffer
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(imageBuffer),
            kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(imageBuffer)
        ]

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(imageBuffer),
            CVPixelBufferGetHeight(imageBuffer),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard let outputBuffer = pixelBuffer else {
            return nil
        }

        context.render(outputImage, to: outputBuffer)
        return outputBuffer
    }

}

/// Sendable bag for AVFoundation reader/writer references used by a single
/// `requestMediaDataWhenReady` pipeline. AVAssetReader/Writer/Input/etc. are
/// reference types not annotated Sendable; in this code path they are touched
/// serially on the same dispatch queue, so wrapping is safe.
private struct UncheckedSendableAVPipeline: @unchecked Sendable {
    let writerInput: AVAssetWriterInput
    let readerOutput: AVAssetReaderTrackOutput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let writer: AVAssetWriter
    let reader: AVAssetReader
}
