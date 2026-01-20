//
//  LocalAIProviderTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
import AVFoundation
@testable import EngineKit

/// Tests for LocalAIProvider implementation
///
/// Tests cover:
/// - Provider initialization and setup
/// - Background generation with procedural generation
/// - Style transfer using CoreImage filters
/// - Camera background replacement (placeholder)
/// - Keyword extraction
/// - Helper methods
/// - Error handling
/// - Performance considerations
@available(macOS 13.0, *)
final class LocalAIProviderTests: XCTestCase {

    var provider: LocalAIProvider!
    var testProjectId: ProjectId!
    var testProjectURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        provider = LocalAIProvider()
        testProjectId = UUID()

        // Create test project directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDirectory = appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true)
        testProjectURL = baseDirectory.appendingPathComponent(testProjectId.uuidString, isDirectory: true)

        try fileManager.createDirectory(at: testProjectURL, withIntermediateDirectories: true)

        // Create sources directory
        let sourcesURL = testProjectURL.appendingPathComponent("sources", isDirectory: true)
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Cleanup test project directory
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: testProjectURL)

        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testProviderInitialization() {
        XCTAssertNotNil(provider, "LocalAIProvider should initialize successfully")
    }

    // MARK: - Background Generation Tests

    func testGenerateBackgroundWithDefaultStyle() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "abstract colorful background",
            width: 1920,
            height: 1080,
            style: .abstract
        )

        XCTAssertEqual(assetRef.type, .image, "Asset type should be image")
        XCTAssertFalse(assetRef.filename.isEmpty, "Filename should not be empty")
        XCTAssertFalse(assetRef.data.isEmpty, "Image data should not be empty")
        XCTAssertNotNil(assetRef.thumbnail, "Thumbnail should be generated")
        XCTAssertEqual(assetRef.metadata["prompt"] as? String, "abstract colorful background")
        XCTAssertEqual(assetRef.metadata["width"] as? String, "1920")
        XCTAssertEqual(assetRef.metadata["height"] as? String, "1080")
        XCTAssertEqual(assetRef.metadata["style"] as? String, "abstract")
    }

    func testGenerateBackgroundWithGradientStyle() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "smooth gradient background",
            width: 1280,
            height: 720,
            style: .gradient
        )

        XCTAssertEqual(assetRef.type, .image)
        XCTAssertFalse(assetRef.data.isEmpty)
        XCTAssertEqual(assetRef.metadata["style"] as? String, "gradient")
    }

    func testGenerateBackgroundWithMinimalStyle() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "simple clean background",
            width: 800,
            height: 600,
            style: .minimal
        )

        XCTAssertEqual(assetRef.type, .image)
        XCTAssertFalse(assetRef.data.isEmpty)
        XCTAssertEqual(assetRef.metadata["style"] as? String, "minimal")
    }

    func testGenerateBackgroundWithWarmKeywords() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "warm sunny background",
            width: 1920,
            height: 1080,
            style: .gradient
        )

        XCTAssertFalse(assetRef.data.isEmpty)
        // Warm keywords should affect the generated image
        XCTAssertEqual(assetRef.metadata["prompt"] as? String, "warm sunny background")
    }

    func testGenerateBackgroundWithCoolKeywords() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "cool calm background",
            width: 1920,
            height: 1080,
            style: .gradient
        )

        XCTAssertFalse(assetRef.data.isEmpty)
        XCTAssertEqual(assetRef.metadata["prompt"] as? String, "cool calm background")
    }

    func testGenerateBackgroundWithDifferentResolutions() async throws {
        // Test 4K resolution
        let asset4K = try await provider.generateBackground(
            prompt: "4K background",
            width: 3840,
            height: 2160,
            style: .abstract
        )

        XCTAssertFalse(asset4K.data.isEmpty)
        XCTAssertEqual(asset4K.metadata["width"] as? String, "3840")
        XCTAssertEqual(asset4K.metadata["height"] as? String, "2160")

        // Test vertical video
        let assetVertical = try await provider.generateBackground(
            prompt: "vertical background",
            width: 1080,
            height: 1920,
            style: .minimal
        )

        XCTAssertFalse(assetVertical.data.isEmpty)
        XCTAssertEqual(assetVertical.metadata["width"] as? String, "1080")
        XCTAssertEqual(assetVertical.metadata["height"] as? String, "1920")
    }

    func testGenerateBackgroundThumbnailGeneration() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "test background",
            width: 1920,
            height: 1080,
            style: .abstract
        )

        XCTAssertNotNil(assetRef.thumbnail, "Thumbnail should be generated")
        XCTAssertFalse(assetRef.thumbnail!.isEmpty, "Thumbnail data should not be empty")

        // Verify thumbnail is JPEG
        let headers = assetRef.thumbnail!.prefix(4).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(headers == "ffd8" || headers == "ffd8ff", "Thumbnail should be JPEG format")
    }

    // MARK: - Style Transfer Tests

    func testStyleTransferWithMissingSourceFile() async throws {
        // Don't create source file - should fail
        do {
            _ = try await provider.applyStyleTransfer(
                projectId: testProjectId,
                style: "sepia",
                strength: 0.5
            )
            XCTFail("Should throw error for missing source file")
        } catch AIServiceError.generationFailed(let message) {
            XCTAssertTrue(message.contains("Source video not found"), "Error should mention missing source")
        }
    }

    func testStyleTransferWithSepiaFilter() async throws {
        // Create a simple test video
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        let assetRef = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "sepia",
            strength: 0.5
        )

        XCTAssertEqual(assetRef.type, .styledVideo, "Asset type should be styledVideo")
        XCTAssertFalse(assetRef.filename.isEmpty, "Filename should not be empty")
        XCTAssertNotNil(assetRef.url, "URL should be set")
        XCTAssertEqual(assetRef.metadata["style"] as? String, "sepia")
        XCTAssertEqual(assetRef.metadata["strength"] as? String, "0.5")
        XCTAssertEqual(assetRef.metadata["filter"] as? String, "CISepiaTone")
    }

    func testStyleTransferWithNoirFilter() async throws {
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        let assetRef = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "noir",
            strength: 0.8
        )

        XCTAssertEqual(assetRef.type, .styledVideo)
        XCTAssertEqual(assetRef.metadata["style"] as? String, "noir")
        XCTAssertEqual(assetRef.metadata["strength"] as? String, "0.8")
    }

    func testStyleTransferWithChromeFilter() async throws {
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        let assetRef = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "chrome",
            strength: 1.0
        )

        XCTAssertEqual(assetRef.type, .styledVideo)
        XCTAssertEqual(assetRef.metadata["style"] as? String, "chrome")
        XCTAssertEqual(assetRef.metadata["strength"] as? String, "1.0")
    }

    func testStyleTransferWithVignetteFilter() async throws {
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        let assetRef = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "vignette",
            strength: 0.6
        )

        XCTAssertEqual(assetRef.type, .styledVideo)
        XCTAssertEqual(assetRef.metadata["style"] as? String, "vignette")
        XCTAssertEqual(assetRef.metadata["strength"] as? String, "0.6")
    }

    func testStyleTransferWithDifferentStrengths() async throws {
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        // Test minimum strength
        let minStrength = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "sepia",
            strength: 0.0
        )
        XCTAssertEqual(minStrength.metadata["strength"] as? String, "0.0")

        // Test maximum strength
        let maxStrength = try await provider.applyStyleTransfer(
            projectId: testProjectId,
            style: "sepia",
            strength: 1.0
        )
        XCTAssertEqual(maxStrength.metadata["strength"] as? String, "1.0")
    }

    // MARK: - Camera Background Replacement Tests

    func testReplaceCameraBackgroundWithMissingCameraFile() async throws {
        // Create a test background asset
        let backgroundAsset = try await provider.generateBackground(
            prompt: "test background",
            width: 1920,
            height: 1080,
            style: .gradient
        )

        // Don't create camera file - should fail
        do {
            _ = try await provider.replaceCameraBackground(
                projectId: testProjectId,
                background: backgroundAsset,
                edgeSmoothness: 0.5
            )
            XCTFail("Should throw error for missing camera file")
        } catch AIServiceError.generationFailed(let message) {
            XCTAssertTrue(message.contains("Camera video not found"), "Error should mention missing camera file")
        }
    }

    func testReplaceCameraBackgroundIsExperimental() async throws {
        // Create camera file
        let cameraPath = testProjectURL.appendingPathComponent("sources/camera.mov")
        try createTestVideo(at: cameraPath, duration: 1.0, width: 1280, height: 720)

        let backgroundAsset = try await provider.generateBackground(
            prompt: "test background",
            width: 1920,
            height: 1080,
            style: .gradient
        )

        // Background replacement is experimental and should fail with specific message
        do {
            _ = try await provider.replaceCameraBackground(
                projectId: testProjectId,
                background: backgroundAsset,
                edgeSmoothness: 0.5
            )
            XCTFail("Should throw error for experimental feature")
        } catch AIServiceError.generationFailed(let message) {
            XCTAssertTrue(message.contains("experimental"), "Error should mention experimental feature")
            XCTAssertTrue(message.contains("Vision framework"), "Error should mention Vision framework requirement")
        }
    }

    // MARK: - Keyword Extraction Tests

    func testKeywordExtractionWithSimplePrompt() {
        // Since extractKeywords is private, we test it indirectly through background generation
        // Keywords from "blue sky" should be ["blue", "sky"]
        // (without common stop words)
    }

    func testKeywordExtractionWithComplexPrompt() async throws {
        // Complex prompt with multiple keywords
        let assetRef = try await provider.generateBackground(
            prompt: "warm colorful abstract gradient background with high contrast",
            width: 1920,
            height: 1080,
            style: .gradient
        )

        XCTAssertFalse(assetRef.data.isEmpty)
        XCTAssertEqual(assetRef.metadata["prompt"] as? String, "warm colorful abstract gradient background with high contrast")
    }

    // MARK: - AssetRef Tests

    func testAssetRefCreationForGeneratedBackground() async throws {
        let assetRef = try await provider.generateBackground(
            prompt: "test background",
            width: 1920,
            height: 1080,
            style: .abstract
        )

        // Verify all AssetRef fields are populated
        XCTAssertNotNil(assetRef.type)
        XCTAssertFalse(assetRef.filename.isEmpty)
        XCTAssertFalse(assetRef.data.isEmpty)
        XCTAssertNotNil(assetRef.thumbnail)
        XCTAssertFalse(assetRef.metadata.isEmpty)

        // Verify PNG data format
        let headers = assetRef.data.prefix(8).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(headers == "89504e470d0a1a0a", "Image data should be PNG format")
    }

    func testAssetRefEquality() async throws {
        let assetRef1 = try await provider.generateBackground(
            prompt: "test",
            width: 1920,
            height: 1080,
            style: .abstract
        )

        let assetRef2 = try await provider.generateBackground(
            prompt: "test",
            width: 1920,
            height: 1080,
            style: .abstract
        )

        // AssetRefs should not be equal (different filenames)
        XCTAssertNotEqual(assetRef1.filename, assetRef2.filename, "Each generation should create unique filename")
    }

    // MARK: - Performance Tests

    func testBackgroundGenerationPerformance() async throws {
        measure {
            let expectation = self.expectation(description: "Background generation")

            Task {
                _ = try await self.provider.generateBackground(
                    prompt: "performance test background",
                    width: 1920,
                    height: 1080,
                    style: .gradient
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testStyleTransferPerformance() async throws {
        let screenPath = testProjectURL.appendingPathComponent("sources/screen.mov")
        try createTestVideo(at: screenPath, duration: 1.0, width: 1280, height: 720)

        measure {
            let expectation = self.expectation(description: "Style transfer")

            Task {
                _ = try await self.provider.applyStyleTransfer(
                    projectId: self.testProjectId,
                    style: "sepia",
                    strength: 0.5
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    // MARK: - Helper Methods

    /// Create a simple test video file
    private func createTestVideo(at url: URL, duration: Double, width: Int, height: Int) throws {
        let size = CGSize(width: width, height: height)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "test_video")) {
            let frameRate: Double = 30
            let frameCount = Int(duration * frameRate)
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

            for frameIndex in 0..<frameCount {
                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }

                var pixelBuffer: CVPixelBuffer?
                let attrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]

                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    width,
                    height,
                    kCVPixelFormatType_32ARGB,
                    attrs as CFDictionary,
                    &pixelBuffer
                )

                if let buffer = pixelBuffer {
                    // Fill with a simple color pattern
                    CVPixelBufferLockBaseAddress(buffer, [])
                    let context = CGContext(
                        data: CVPixelBufferGetBaseAddress(buffer),
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    )

                    if let ctx = context {
                        // Create a simple gradient pattern
                        let progress = Double(frameIndex) / Double(frameCount)
                        let color = CGColor(
                            red: CGFloat(progress),
                            green: 0.5,
                            blue: 1.0 - CGFloat(progress),
                            alpha: 1.0
                        )
                        ctx.setFillColor(color)
                        ctx.fill(CGRect(origin: .zero, size: size))
                    }

                    CVPixelBufferUnlockBaseAddress(buffer, [])

                    let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))
                    adaptor.append(buffer, withPresentationTime: presentationTime)
                }
            }

            writerInput.markAsFinished()
            writer.finishWriting {
                // Video creation complete
            }
        }

        // Wait for writing to complete
        while writer.status == .writing {
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertEqual(writer.status, .completed, "Video writing should complete successfully")
    }
}
