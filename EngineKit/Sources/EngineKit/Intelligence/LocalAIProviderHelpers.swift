//
//  LocalAIProviderHelpers.swift
//  EngineKit
//
//  Extracted from LocalAIProvider.swift — procedural generation helpers, style mapping, and utilities
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

extension LocalAIProvider {
    // MARK: - Background Generation Helpers

    /// Extract keywords from prompt for procedural generation
    func extractKeywords(from prompt: String) -> [String] {
        // Simple keyword extraction: split by spaces and filter common words
        let stopWords = ["the", "a", "an", "is", "are", "was", "were", "with", "and", "or", "but"]
        let words = prompt.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return words
    }

    /// Generate procedural image using CoreImage filters
    func generateProceduralImage(
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
    func applyProceduralEffects(
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
    func applyAbstractStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
        // CIRandomGenerator is a generator filter with no inputs — it produces
        // infinite random noise on its own; crop it to the target extent instead
        // of feeding it an input image (setting kCIInputImageKey on it throws
        // NSUnknownKeyException since the filter doesn't declare that input).
        let noiseGenerator = CIFilter(name: "CIRandomGenerator")!
        let noise = noiseGenerator.outputImage?.cropped(to: image.extent)

        // Apply blur for soft effect
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(noise, forKey: kCIInputImageKey)
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
    func applyGradientStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
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

        // Gradient generators fill an infinite plane; crop back to the target
        // extent or createCGImage(_:from:) fails downstream.
        guard let output = gradientFilter.outputImage else { return image }
        return output.cropped(to: image.extent)
    }

    /// Apply minimal style (simple solid/gradient)
    func applyMinimalStyle(to image: CIImage, keywords: [String]) throws -> CIImage {
        // Create simple gradient
        let gradientFilter = CIFilter(name: "CISmoothLinearGradient")!
        gradientFilter.setValue(CIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0), forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0), forKey: "inputColor1")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: 0, y: 0)), forKey: "inputPoint0")
        gradientFilter.setValue(CIVector(cgPoint: CGPoint(x: image.extent.width, y: image.extent.height)), forKey: "inputPoint1")

        // Same infinite-extent caveat as applyGradientStyle.
        guard let output = gradientFilter.outputImage else { return image }
        return output.cropped(to: image.extent)
    }

    // MARK: - Style Transfer Helpers

    /// Map style names to CoreImage filter names
    func mapStyleToFilter(_ style: String) -> String {
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

    // MARK: - Background Replacement Helpers

    /// Load image from AssetRef
    func loadImage(from assetRef: AssetRef) throws -> CIImage {
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
    func performBackgroundReplacement(
        inputURL: URL,
        background: CIImage,
        edgeSmoothness: Double
    ) async throws -> URL {
        throw AIServiceError.generationFailed(
            "Background replacement is experimental and requires Vision framework integration. " +
            "This is a placeholder for the Labs feature."
        )
    }

    /// Generate thumbnail from image data
    func generateThumbnail(from imageData: Data, size: CGSize = CGSize(width: 200, height: 200)) -> Data? {
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
    func projectURL(for projectId: ProjectId) -> URL {
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
