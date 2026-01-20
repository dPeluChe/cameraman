//
//  AIServiceTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Comprehensive test suite for AIService
final class AIServiceTests: XCTestCase {
    private var aiService: AIService!
    private var jobQueue: JobQueue!
    private var projectStore: ProjectStore!
    private var testProjectId: ProjectId!
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        jobQueue = JobQueue()
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent("AIServiceTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        projectStore = ProjectStore(baseDirectory: tempDirectory)
        aiService = AIService(
            jobQueue: jobQueue,
            projectStore: projectStore,
            projectDirectoryOverride: tempDirectory
        )
        testProjectId = UUID()

        // Initialize EngineKit
        EngineKit.initialize(logLevel: .debug, enableConsoleLogging: false)
    }

    override func tearDown() async throws {
        aiService = nil
        jobQueue = nil
        projectStore = nil
        testProjectId = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil

        try await super.tearDown()
    }

    // MARK: - AIService Initialization Tests

    func testAIServiceInitialization() {
        XCTAssertNotNil(aiService, "AIService should be initialized")
    }

    func testAIServiceHasNoProviderByDefault() async {
        let hasProvider = await aiService.hasProvider()
        XCTAssertFalse(hasProvider, "AIService should not have a provider by default")
    }

    // MARK: - Provider Management Tests

    func testSetProvider() async throws {
        let mockProvider = MockAIProvider()
        await aiService.setProvider(mockProvider)

        let hasProvider = await aiService.hasProvider()
        XCTAssertTrue(hasProvider, "AIService should have a provider after setting one")
    }

    func testClearProvider() async throws {
        let mockProvider = MockAIProvider()
        await aiService.setProvider(mockProvider)

        let hasProvider1 = await aiService.hasProvider()
        XCTAssertTrue(hasProvider1)

        await aiService.clearProvider()

        let hasProvider2 = await aiService.hasProvider()
        XCTAssertFalse(hasProvider2, "AIService should not have a provider after clearing")
    }

    // MARK: - Suggestion Model Tests

    func testSuggestionModelCreation() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Remove Silence",
            description: "Remove silent region from 10s to 15s",
            confidence: 0.9,
            timelineIn: 10.0,
            timelineOut: 15.0,
            metadata: ["duration": 5.0]
        )

        XCTAssertEqual(suggestion.type, .removeSilence)
        XCTAssertEqual(suggestion.title, "Remove Silence")
        XCTAssertEqual(suggestion.confidence, 0.9)
        XCTAssertEqual(suggestion.timelineIn, 10.0)
        XCTAssertEqual(suggestion.timelineOut, 15.0)
        XCTAssertEqual(suggestion.metadata("duration", as: Double.self), 5.0)
    }

    func testSuggestionModelEquality() {
        let id = UUID()
        let suggestion1 = Suggestion(
            id: id,
            type: .createChapter,
            title: "Chapter 1",
            description: "Introduction",
            confidence: 0.8,
            timelineIn: 0.0,
            timelineOut: 30.0
        )

        let suggestion2 = Suggestion(
            id: id,
            type: .createChapter,
            title: "Chapter 1",
            description: "Introduction",
            confidence: 0.8,
            timelineIn: 0.0,
            timelineOut: 30.0
        )

        XCTAssertEqual(suggestion1, suggestion2, "Suggestions with same properties should be equal")
    }

    func testSuggestionTypeEnum() {
        XCTAssertEqual(SuggestionType.removeSilence.rawValue, "removeSilence")
        XCTAssertEqual(SuggestionType.createChapter.rawValue, "createChapter")
        XCTAssertEqual(SuggestionType.suggestCut.rawValue, "suggestCut")
        XCTAssertEqual(SuggestionType.suggestOverlay.rawValue, "suggestOverlay")
        XCTAssertEqual(SuggestionType.suggestZoom.rawValue, "suggestZoom")
        XCTAssertEqual(SuggestionType.suggestBackground.rawValue, "suggestBackground")
    }

    // MARK: - AssetRef Model Tests

    func testAssetRefModelCreation() {
        let data = Data([0x00, 0x01, 0x02])
        let assetRef = AssetRef(
            type: .image,
            filename: "background.png",
            data: data,
            url: nil,
            thumbnail: nil
        )

        XCTAssertEqual(assetRef.type, .image)
        XCTAssertEqual(assetRef.filename, "background.png")
        XCTAssertEqual(assetRef.data, data)
        XCTAssertNil(assetRef.url)
        XCTAssertNil(assetRef.thumbnail)
    }

    func testAssetRefModelEquality() {
        let id = UUID()
        let data = Data([0x00, 0x01, 0x02])
        let assetRef1 = AssetRef(
            id: id,
            type: .image,
            filename: "background.png",
            data: data
        )

        let assetRef2 = AssetRef(
            id: id,
            type: .image,
            filename: "background.png",
            data: data
        )

        XCTAssertEqual(assetRef1, assetRef2, "AssetRefs with same properties should be equal")
    }

    func testAssetTypeEnum() {
        XCTAssertEqual(AssetType.image.rawValue, "image")
        XCTAssertEqual(AssetType.video.rawValue, "video")
        XCTAssertEqual(AssetType.styledVideo.rawValue, "styledVideo")
        XCTAssertEqual(AssetType.processedCamera.rawValue, "processedCamera")
    }

    // MARK: - Options Model Tests

    func testSilenceDetectionOptionsDefault() {
        let options = SilenceDetectionOptions.default

        XCTAssertEqual(options.silenceThreshold, -40.0)
        XCTAssertEqual(options.minSilenceDuration, 1.0)
        XCTAssertTrue(options.autoCreateCuts)
    }

    func testSilenceDetectionOptionsSensitive() {
        let options = SilenceDetectionOptions.sensitive

        XCTAssertEqual(options.silenceThreshold, -50.0)
        XCTAssertEqual(options.minSilenceDuration, 0.5)
    }

    func testSilenceDetectionOptionsAggressive() {
        let options = SilenceDetectionOptions.aggressive

        XCTAssertEqual(options.silenceThreshold, -30.0)
        XCTAssertEqual(options.minSilenceDuration, 2.0)
    }

    func testChapterSuggestionOptionsDefault() {
        let options = ChapterSuggestionOptions.default

        XCTAssertEqual(options.minChapterDuration, 30.0)
        XCTAssertEqual(options.maxChapters, 20)
        XCTAssertFalse(options.useTopicDetection)
    }

    func testChapterSuggestionOptionsShortChapters() {
        let options = ChapterSuggestionOptions.shortChapters

        XCTAssertEqual(options.minChapterDuration, 15.0)
        XCTAssertEqual(options.maxChapters, 40)
    }

    func testChapterSuggestionOptionsLongChapters() {
        let options = ChapterSuggestionOptions.longChapters

        XCTAssertEqual(options.minChapterDuration, 60.0)
        XCTAssertEqual(options.maxChapters, 10)
    }

    func testBackgroundGenerationOptionsDefault() {
        let options = BackgroundGenerationOptions.default

        XCTAssertEqual(options.width, 1920)
        XCTAssertEqual(options.height, 1080)
        XCTAssertEqual(options.style, .gradient)
    }

    func testBackgroundGenerationOptionsFourK() {
        let options = BackgroundGenerationOptions.fourK

        XCTAssertEqual(options.width, 3840)
        XCTAssertEqual(options.height, 2160)
    }

    func testBackgroundGenerationOptionsVertical() {
        let options = BackgroundGenerationOptions.vertical

        XCTAssertEqual(options.width, 1080)
        XCTAssertEqual(options.height, 1920)
    }

    func testStyleTransferOptionsDefault() {
        let options = StyleTransferOptions.default

        XCTAssertEqual(options.strength, 0.7)
        XCTAssertTrue(options.preserveColors)
        XCTAssertEqual(options.quality, .normal)
    }

    func testStyleTransferOptionsSubtle() {
        let options = StyleTransferOptions.subtle

        XCTAssertEqual(options.strength, 0.3)
    }

    func testStyleTransferOptionsStrong() {
        let options = StyleTransferOptions.strong

        XCTAssertEqual(options.strength, 0.95)
    }

    func testBackgroundReplacementOptionsDefault() {
        let options = BackgroundReplacementOptions.default

        XCTAssertEqual(options.edgeSmoothness, 0.5)
        XCTAssertTrue(options.adjustLighting)
        XCTAssertEqual(options.quality, .normal)
    }

    // MARK: - Style Enum Tests

    func testBackgroundStyleEnum() {
        XCTAssertEqual(BackgroundStyle.gradient.rawValue, "gradient")
        XCTAssertEqual(BackgroundStyle.solid.rawValue, "solid")
        XCTAssertEqual(BackgroundStyle.pattern.rawValue, "pattern")
        XCTAssertEqual(BackgroundStyle.abstract.rawValue, "abstract")
        XCTAssertEqual(BackgroundStyle.minimal.rawValue, "minimal")
        XCTAssertEqual(BackgroundStyle.professional.rawValue, "professional")
        XCTAssertEqual(BackgroundStyle.creative.rawValue, "creative")
    }

    // MARK: - AIServiceError Tests

    func testAIServiceErrorDescriptions() {
        let errors: [AIServiceError] = [
            .noAudioTrack,
            .transcriptNotFound,
            .noProviderConfigured,
            .audioAnalysisFailed("test"),
            .providerError("test"),
            .invalidAsset,
            .generationFailed("test")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
        }
    }

    func testAIServiceErrorNoAudioTrackDescription() {
        let error = AIServiceError.noAudioTrack
        XCTAssertEqual(error.errorDescription, "No audio track found in project")
    }

    func testAIServiceErrorTranscriptNotFoundDescription() {
        let error = AIServiceError.transcriptNotFound
        XCTAssertEqual(error.errorDescription, "Transcript not found. Please run transcription first.")
    }

    func testAIServiceErrorNoProviderConfiguredDescription() {
        let error = AIServiceError.noProviderConfigured
        XCTAssertEqual(error.errorDescription, "No AI provider configured")
    }

    // MARK: - AIAnyCodable Tests

    func testAIAnyCodableInt() throws {
        let value = 42
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? Int), 42)
    }

    func testAIAnyCodableString() throws {
        let value = "test"
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? String), "test")
    }

    func testAIAnyCodableDouble() throws {
        let value = 3.14
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? Double), 3.14)
    }

    func testAIAnyCodableBool() throws {
        let value = true
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? Bool), true)
    }

    func testAIAnyCodableArray() throws {
        let value = [1, 2, 3]
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? [Int]), [1, 2, 3])
    }

    func testAIAnyCodableDictionary() throws {
        let value = ["key": "value"]
        let codable = AIAnyCodable(value)

        let encoder = JSONEncoder()
        let data = try encoder.encode(codable)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIAnyCodable.self, from: data)

        XCTAssertEqual((decoded.value as? [String: String]), ["key": "value"])
    }

    // MARK: - Cloud Provider Tests

    func testGenerateBackgroundWithoutProvider() async throws {
        do {
            _ = try await aiService.generateBackground(
                projectId: testProjectId,
                prompt: "Abstract gradient"
            )
            XCTFail("Should throw error when no provider is configured")
        } catch AIServiceError.noProviderConfigured {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testApplyStyleTransferWithoutProvider() async throws {
        do {
            _ = try await aiService.applyStyleTransfer(
                projectId: testProjectId,
                style: "cartoon"
            )
            XCTFail("Should throw error when no provider is configured")
        } catch AIServiceError.noProviderConfigured {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testReplaceCameraBackgroundWithoutProvider() async throws {
        let assetRef = AssetRef(type: .image, filename: "bg.png", data: Data())

        do {
            _ = try await aiService.replaceCameraBackground(
                projectId: testProjectId,
                background: assetRef
            )
            XCTFail("Should throw error when no provider is configured")
        } catch AIServiceError.noProviderConfigured {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGenerateBackgroundWithProvider() async throws {
        let mockProvider = MockAIProvider()
        await aiService.setProvider(mockProvider)

        let jobId = try await aiService.generateBackground(
            projectId: testProjectId,
            prompt: "Abstract gradient",
            options: .default
        )

        // Verify job was created
        let job = await jobQueue.getJob(jobId: jobId)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.type, .aiGeneration)

        // Wait for completion (with timeout)
        let expectation = expectation(description: "Job completes")
        let task = Task {
            while true {
                let job = await jobQueue.getJob(jobId: jobId)
                if case .success = job?.status {
                    expectation.fulfill()
                    break
                }
                if case .failed = job?.status {
                    XCTFail("Job failed")
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
        }

        try await Task.sleep(for: .seconds(5))
        task.cancel()
        await fulfillment(of: [expectation], timeout: 5)
    }

    // MARK: - Suggestion Metadata Tests

    func testSuggestionMetadataExtraction() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Remove Silence",
            description: "Test",
            confidence: 0.9,
            timelineIn: 0.0,
            timelineOut: 5.0,
            metadata: [
                "duration": 5.0,
                "threshold": -40.0,
                "text": "silence"
            ]
        )

        XCTAssertEqual(suggestion.metadata("duration", as: Double.self), 5.0)
        XCTAssertEqual(suggestion.metadata("threshold", as: Double.self), -40.0)
        XCTAssertEqual(suggestion.metadata("text", as: String.self), "silence")
        XCTAssertNil(suggestion.metadata("nonexistent", as: String.self))
    }

    // MARK: - Performance Tests

    func testSuggestionCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = Suggestion(
                    id: UUID(),
                    type: .removeSilence,
                    title: "Test",
                    description: "Test description",
                    confidence: 0.9,
                    timelineIn: 0.0,
                    timelineOut: 5.0
                )
            }
        }
    }

    func testAssetRefCreationPerformance() {
        let data = Data(repeating: 0, count: 1024)

        measure {
            for _ in 0..<1000 {
                _ = AssetRef(
                    type: .image,
                    filename: "test.png",
                    data: data
                )
            }
        }
    }

    func testOptionsCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = SilenceDetectionOptions.default
                _ = ChapterSuggestionOptions.default
                _ = BackgroundGenerationOptions.default
                _ = StyleTransferOptions.default
                _ = BackgroundReplacementOptions.default
            }
        }
    }
}

// MARK: - Mock AI Provider

/// Mock AI provider for testing
actor MockAIProvider: AIProvider {
    var shouldFail = false
    var delay: TimeInterval = 0.1

    func generateBackground(
        prompt: String,
        width: Int,
        height: Int,
        style: BackgroundStyle
    ) async throws -> AssetRef {
        if shouldFail {
            throw AIServiceError.generationFailed("Mock failure")
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Return mock image data
        let mockData = Data(repeating: 0xFF, count: 1024)
        return AssetRef(
            type: .image,
            filename: "mock_background.png",
            data: mockData,
            url: nil,
            thumbnail: nil,
            metadata: ["prompt": prompt]
        )
    }

    func applyStyleTransfer(
        projectId: ProjectId,
        style: String,
        strength: Double
    ) async throws -> AssetRef {
        if shouldFail {
            throw AIServiceError.generationFailed("Mock failure")
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let mockData = Data(repeating: 0xAA, count: 2048)
        return AssetRef(
            type: .styledVideo,
            filename: "styled_video.mp4",
            data: mockData
        )
    }

    func replaceCameraBackground(
        projectId: ProjectId,
        background: AssetRef,
        edgeSmoothness: Double
    ) async throws -> AssetRef {
        if shouldFail {
            throw AIServiceError.generationFailed("Mock failure")
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let mockData = Data(repeating: 0xBB, count: 3072)
        return AssetRef(
            type: .processedCamera,
            filename: "camera_processed.mp4",
            data: mockData
        )
    }
}
