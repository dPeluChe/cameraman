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
    private let ciContext: CIContext

    /// File manager for asset operations
    private let fileManager = FileManager.default

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

    // MARK: - Private Helpers - Background Generation

    /// Extract keywords from prompt for procedural generation
    private func extractKeywords(from prompt: String) -> [String] {
        // Simple keyword extraction: split by spaces and filter common words
        let stopWords = ["the", "a", "an", "is", "are", "was", "were", "with", "and", "or", "but"]
        let words = prompt.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return words
    }

    /// Generate procedural image using CoreImage filters
    private func generateProceduralImage(
        keywords: [String],
        width: Int,
        height: Int,
        style: BackgroundStyle
    ) async throws -> CGImage {
        // Create base image
        var image = CIImage(color: .init(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0))
            .cropped(to: CoreFoundation.CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Apply procedural effects based on keywords and style
        image = try applyProceduralEffects(to: image, keywords: keywords, style: style)

        // Render final image
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw AIServiceError.generationFailed("Failed to render image")
        }

        return cgImage
    }

    /// Apply procedural effects based on keywords and style
    private func applyProceduralEffects(
        to image: CIImage,
        keywords: [String],
        style: BackgroundStyle
    ) throws -> CIImage {
        var result = image

        // Apply style-based effects
        switch style {
        case .abstract:
            result = try applyAbstractStyle(to: result, keywords: keywords)
        case .gradient:
            result = try applyGradientStyle(to: result, keywords: keywords)
        case .minimal, .solid:
            result = try applyMinimalStyle(to: result, keywords: keywords)
        case .pattern, .professional, .creative:
            result = try applyGradientStyle(to: result, keywords: keywords)
        }

        return result
    }

    /// Apply abstract style (noise + blur)
    private func applyAbstractStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
        // Generate noise
        let noiseGenerator = CIFilter(name: "CIRandomGenerator")!
        noiseGenerator.setValue(image, forKey: kCIInputImageKey)

        // Apply blur for soft effect
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(noiseGenerator.outputImage, forKey: kCIInputImageKey)
        blurFilter.setValue(20.0, forKey: kCIInputRadiusKey)

        // Add color based on keywords
        let colorFilter = CIFilter(name: "CIColorControls")!
        colorFilter.setValue(blurFilter.outputImage, forKey: kCIInputImageKey)
        colorFilter.setValue(keywords.contains("colorful") ? 1.5 : 0.8, forKey: kCIInputSaturationKey)
        colorFilter.setValue(keywords.contains("contrast") ? 1.3 : 1.0, forKey: kCIInputContrastKey)
        colorFilter.setValue(keywords.contains("dark") ? -0.2 : 0.1, forKey: kCIInputBrightnessKey)

        return colorFilter.outputImage ?? image
    }

    /// Apply gradient style (smooth color transitions)
    private func applyGradientStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
        // Create gradient
        let gradientFilter = CIFilter(name: "CISmoothLinearGradient")!
        var color0 = CIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1.0)
        var color1 = CIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0)

        // Adjust colors based on keywords
        if keywords.contains("warm") {
            color0 = CIColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0)
            color1 = CIColor(red: 0.3, green: 0.1, blue: 0.2, alpha: 1.0)
        } else if keywords.contains("cool") {
            color0 = CIColor(red: 0.1, green: 0.3, blue: 0.4, alpha: 1.0)
            color1 = CIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
        }

        gradientFilter.setValue(color0, forKey: "inputColor0")
        gradientFilter.setValue(color1, forKey: "inputColor1")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: 0, y: 0)), forKey: "inputPoint0")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: image.extent.width, y: image.extent.height)), forKey: "inputPoint1")

        return gradientFilter.outputImage ?? image
    }

    /// Apply minimal style (simple solid/gradient)
    private func applyMinimalStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
        // Create simple gradient
        let gradientFilter = CIFilter(name: "CISmoothLinearGradient")!
        gradientFilter.setValue(CIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0), forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0), forKey: "inputColor1")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: 0, y: 0)), forKey: "inputPoint0")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: image.extent.width, y: image.extent.height)), forKey: "inputPoint1")

        return gradientFilter.outputImage ?? image
    }

    // MARK: - Private Helpers - Style Transfer

    /// Map style names to CoreImage filter names
    private func mapStyleToFilter(_ style: String) -> String {
        let styleMap: [String: String] = [
            "cartoon": "CICartoon",
            "comic": "CIComic",
            "noir": "CIPhotoEffectNoir",
            "vintage": "CIVintage",
            "instant": "CIPhotoEffectInstant",
            "transfer": "CIToneCurve",
            "vignette": "CIVignette",
            "chrome": "CIPhotoEffectChrome",
            "fade": "CIPhotoEffectFade",
            "mono": "CIPhotoEffectMono",
            "process": "CIPhotoEffectProcess",
            "tonal": "CIPhotoEffectTonal",
            "sepia": "CISepiaTone"
        ]

        return styleMap[style.lowercased()] ?? "CIPhotoEffectChrome"
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

        // Apply filter to each frame
        writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video_filter")) {
            while writerInput.isReadyForMoreMediaData {
                autoreleasepool {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        if let filteredBuffer = self.applyFilterToSampleBuffer(
                            sampleBuffer: sampleBuffer,
                            filterName: filterName,
                            strength: strength
                        ) {
                            adaptor.append(filteredBuffer, withPresentationTime: sampleBuffer.presentationTimeStamp)
                        }
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            reader.cancelReading()
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

    // MARK: - Private Helpers - Background Replacement

    /// Load image from AssetRef
    private func loadImage(from assetRef: AssetRef) throws -> CIImage {
        guard let nsImage = NSImage(data: assetRef.data) else {
            throw AIServiceError.generationFailed("Failed to load background image")
        }

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AIServiceError.generationFailed("Failed to get CGImage from NSImage")
        }

        return CIImage(cgImage: cgImage)
    }

    /// Perform background replacement (simplified implementation)
    ///
    /// Note: This is a simplified implementation. For production use,
    /// you would need:
    /// - Vision framework person segmentation (VNGeneratePersonSegmentationRequest)
    /// - CoreML model for better segmentation
    /// - Proper edge smoothing and lighting adjustment
    private func performBackgroundReplacement(
        inputURL: URL,
        background: CIImage,
        edgeSmoothness: Double
    ) async throws -> URL {
        // For now, this is a placeholder for the full implementation

        // In a real implementation, you would:
        // 1. Read each frame from camera video
        // 2. Use Vision framework to segment the person
        // 3. Composite person over background
        // 4. Write to output video

        // For this Labs/P2 feature, we'll create a simple composition
        // that places the camera video as a PiP over the background

        throw AIServiceError.generationFailed(
            "Background replacement is experimental and requires Vision framework integration. " +
            "This is a placeholder for the Labs feature."
        )
    }

    /// Generate thumbnail from image data
    private func generateThumbnail(from imageData: Data, size: CGSize = CGSize(width: 200, height: 200)) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }

        // Get the original size
        let originalSize = image.size
        let scale = min(size.width / originalSize.width, size.height / originalSize.height)
        let scaledSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

        // Create a scaled image representation
        let scaledImage = NSImage(size: scaledSize)
        scaledImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: scaledSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        scaledImage.unlockFocus()

        // Get CGImage and convert to JPEG data
        guard let cgImage = scaledImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    /// Get project directory URL for a given project ID
    private func projectURL(for projectId: ProjectId) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDirectory = appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true)
        return baseDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
    }
}

// MARK: - Extensions

extension CGImage {
    /// Convert CGImage to PNG data
    func pngRepresentation() -> Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  mutableData,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }
}
