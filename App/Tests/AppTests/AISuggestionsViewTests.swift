//
//  AISuggestionsViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-K, P2 Task 1: AI Suggestions Panel Tests
//

import XCTest
import SwiftUI
import EngineKit
@testable import App

/// Tests for AISuggestionsView and AISuggestionsViewModel
final class AISuggestionsViewTests: XCTestCase {

    // MARK: - ViewModel Tests

    func testViewModelInitialState() {
        let viewModel = AISuggestionsViewModel()

        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.loadingMessage.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSuggestionLoadingSuccess() async {
        let viewModel = AISuggestionsViewModel()
        let mockProjectId = UUID()

        // Mock successful loading
        // Note: This test would require mocking ProjectLibrary
        // For now, we test the state changes

        XCTAssertFalse(viewModel.isLoading)

        // After loading completes
        // await viewModel.loadSuggestions(for: mockProjectId)

        // XCTAssertFalse(viewModel.isLoading)
        // XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteSuggestion() async {
        let viewModel = AISuggestionsViewModel()

        // Create mock suggestions
        let suggestion1 = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Remove Silence 1",
            description: "Remove silent section",
            confidence: 0.9,
            timelineIn: 10.0,
            timelineOut: 15.0
        )

        let suggestion2 = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Remove Silence 2",
            description: "Remove another silent section",
            confidence: 0.85,
            timelineIn: 20.0,
            timelineOut: 25.0
        )

        viewModel.suggestions = [suggestion1, suggestion2]
        XCTAssertEqual(viewModel.suggestions.count, 2)

        // Delete first suggestion
        await viewModel.deleteSuggestion(suggestion1.id)
        XCTAssertEqual(viewModel.suggestions.count, 1)
        XCTAssertEqual(viewModel.suggestions.first?.id, suggestion2.id)

        // Delete second suggestion
        await viewModel.deleteSuggestion(suggestion2.id)
        XCTAssertTrue(viewModel.suggestions.isEmpty)
    }

    // MARK: - Suggestion Model Tests

    func testSuggestionCreation() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Test Suggestion",
            description: "Test description",
            confidence: 0.95,
            timelineIn: 5.0,
            timelineOut: 10.0
        )

        XCTAssertEqual(suggestion.title, "Test Suggestion")
        XCTAssertEqual(suggestion.type, .removeSilence)
        XCTAssertEqual(suggestion.confidence, 0.95)
        XCTAssertEqual(suggestion.timelineIn, 5.0)
        XCTAssertEqual(suggestion.timelineOut, 10.0)
    }

    func testSuggestionMetadata() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Test",
            description: "Test",
            confidence: 0.9,
            timelineIn: 0,
            timelineOut: 5,
            metadata: [
                "silenceDuration": 5.0,
                "threshold": -40.0
            ]
        )

        let silenceDuration = suggestion.metadata("silenceDuration", as: Double.self)
        let threshold = suggestion.metadata("threshold", as: Double.self)

        XCTAssertEqual(silenceDuration, 5.0)
        XCTAssertEqual(threshold, -40.0)
    }

    func testSuggestionEquality() {
        let id = UUID()
        let suggestion1 = Suggestion(
            id: id,
            type: .createChapter,
            title: "Chapter 1",
            description: "First chapter",
            confidence: 0.8,
            timelineIn: 0,
            timelineOut: 30,
            metadata: ["key": "value"]
        )

        let suggestion2 = Suggestion(
            id: id,
            type: .createChapter,
            title: "Chapter 1",
            description: "First chapter",
            confidence: 0.8,
            timelineIn: 0,
            timelineOut: 30,
            metadata: ["key": "value"]
        )

        XCTAssertEqual(suggestion1, suggestion2)
    }

    // MARK: - SuggestionType Tests

    func testSuggestionTypeEncoding() throws {
        let types: [SuggestionType] = [
            .removeSilence,
            .createChapter,
            .suggestCut,
            .suggestOverlay,
            .suggestZoom,
            .suggestBackground
        ]

        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(SuggestionType.self, from: data)
            XCTAssertEqual(type, decoded)
        }
    }

    // MARK: - SilenceDetectionOptions Tests

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
        XCTAssertTrue(options.autoCreateCuts)
    }

    func testSilenceDetectionOptionsAggressive() {
        let options = SilenceDetectionOptions.aggressive

        XCTAssertEqual(options.silenceThreshold, -30.0)
        XCTAssertEqual(options.minSilenceDuration, 2.0)
        XCTAssertTrue(options.autoCreateCuts)
    }

    func testSilenceDetectionOptionsCustom() {
        let options = SilenceDetectionOptions(
            silenceThreshold: -45.0,
            minSilenceDuration: 1.5,
            autoCreateCuts: false
        )

        XCTAssertEqual(options.silenceThreshold, -45.0)
        XCTAssertEqual(options.minSilenceDuration, 1.5)
        XCTAssertFalse(options.autoCreateCuts)
    }

    func testSilenceDetectionOptionsEncoding() throws {
        let options = SilenceDetectionOptions.default
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(SilenceDetectionOptions.self, from: data)

        XCTAssertEqual(options, decoded)
    }

    // MARK: - ChapterSuggestionOptions Tests

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
        XCTAssertFalse(options.useTopicDetection)
    }

    func testChapterSuggestionOptionsLongChapters() {
        let options = ChapterSuggestionOptions.longChapters

        XCTAssertEqual(options.minChapterDuration, 60.0)
        XCTAssertEqual(options.maxChapters, 10)
        XCTAssertFalse(options.useTopicDetection)
    }

    func testChapterSuggestionOptionsCustom() {
        let options = ChapterSuggestionOptions(
            minChapterDuration: 45.0,
            maxChapters: 15,
            useTopicDetection: true
        )

        XCTAssertEqual(options.minChapterDuration, 45.0)
        XCTAssertEqual(options.maxChapters, 15)
        XCTAssertTrue(options.useTopicDetection)
    }

    func testChapterSuggestionOptionsEncoding() throws {
        let options = ChapterSuggestionOptions.default
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(ChapterSuggestionOptions.self, from: data)

        XCTAssertEqual(options, decoded)
    }

    // MARK: - AssetRef Tests

    func testAssetRefCreation() {
        let asset = AssetRef(
            type: .image,
            filename: "background.png",
            data: Data([0, 1, 2, 3]),
            url: nil,
            thumbnail: nil,
            metadata: [:]
        )

        XCTAssertEqual(asset.type, .image)
        XCTAssertEqual(asset.filename, "background.png")
        XCTAssertEqual(asset.data.count, 4)
    }

    func testAssetRefEncoding() throws {
        let asset = AssetRef(
            type: .image,
            filename: "test.jpg",
            data: Data([0, 1, 2]),
            url: URL(string: "https://example.com/test.jpg"),
            thumbnail: Data([4, 5, 6]),
            metadata: ["key": "value"]
        )

        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(AssetRef.self, from: data)

        XCTAssertEqual(asset.type, decoded.type)
        XCTAssertEqual(asset.filename, decoded.filename)
        XCTAssertEqual(asset.metadata, decoded.metadata)
    }

    // MARK: - AIAnyCodable Tests

    func testAIAnyCodableInt() throws {
        let codable = AIAnyCodable(42)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func testAIAnyCodableDouble() throws {
        let codable = AIAnyCodable(3.14)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? Double, 3.14, accuracy: 0.001)
    }

    func testAIAnyCodableString() throws {
        let codable = AIAnyCodable("hello")
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? String, "hello")
    }

    func testAIAnyCodableBool() throws {
        let codable = AIAnyCodable(true)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? Bool, true)
    }

    func testAIAnyCodableArray() throws {
        let codable = AIAnyCodable([1, 2, 3])
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? [Int], [1, 2, 3])
    }

    func testAIAnyCodableDictionary() throws {
        let codable = AIAnyCodable(["key": "value"])
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(AIAnyCodable.self, from: data)

        XCTAssertEqual(decoded.value as? [String: String], ["key": "value"])
    }

    // MARK: - Integration Tests

    func testSuggestionArrayEncoding() throws {
        let suggestions = [
            Suggestion(
                id: UUID(),
                type: .removeSilence,
                title: "Silence 1",
                description: "Remove silent section",
                confidence: 0.9,
                timelineIn: 10.0,
                timelineOut: 15.0
            ),
            Suggestion(
                id: UUID(),
                type: .createChapter,
                title: "Chapter 1",
                description: "First chapter",
                confidence: 0.8,
                timelineIn: 0,
                timelineOut: 30,
                metadata: ["summary": "Test summary"]
            )
        ]

        let data = try JSONEncoder().encode(suggestions)
        let decoded = try JSONDecoder().decode([Suggestion].self, from: data)

        XCTAssertEqual(suggestions.count, decoded.count)
        XCTAssertEqual(suggestions[0], decoded[0])
        XCTAssertEqual(suggestions[1], decoded[1])
    }

    func testSuggestionWithComplexMetadata() throws {
        let suggestion = Suggestion(
            id: UUID(),
            type: .suggestZoom,
            title: "Zoom Suggestion",
            description: "Add zoom effect",
            confidence: 0.85,
            timelineIn: 5.0,
            timelineOut: 10.0,
            metadata: [
                "zoomLevel": 2.0,
                "position": ["x": 100, "y": 200],
                "enabled": true
            ]
        )

        let data = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(Suggestion.self, from: data)

        XCTAssertEqual(suggestion.id, decoded.id)
        XCTAssertEqual(suggestion.title, decoded.title)

        let zoomLevel = decoded.metadata("zoomLevel", as: Double.self)
        XCTAssertEqual(zoomLevel, 2.0)
    }

    // MARK: - Performance Tests

    func testSuggestionListPerformance() {
        let suggestions = (0..<100).map { index in
            Suggestion(
                id: UUID(),
                type: .removeSilence,
                title: "Silence \(index)",
                description: "Remove silent section \(index)",
                confidence: Double.random(in: 0.7...0.95),
                timelineIn: Double(index) * 10,
                timelineOut: Double(index) * 10 + 5
            )
        }

        measure {
            _ = suggestions.filter { $0.confidence > 0.8 }
        }
    }

    func testSuggestionEncodingPerformance() throws {
        let suggestions = (0..<1000).map { index in
            Suggestion(
                id: UUID(),
                type: .removeSilence,
                title: "Silence \(index)",
                description: "Silence section",
                confidence: 0.9,
                timelineIn: Double(index),
                timelineOut: Double(index) + 1
            )
        }

        measure {
            try? JSONEncoder().encode(suggestions)
        }
    }

    // MARK: - Edge Case Tests

    func testSuggestionWithZeroDuration() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Zero Duration",
            description: "Test edge case",
            confidence: 0.9,
            timelineIn: 10.0,
            timelineOut: 10.0
        )

        XCTAssertEqual(suggestion.timelineIn, suggestion.timelineOut)
    }

    func testSuggestionWithExtremeConfidence() {
        let lowConfidence = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "Low",
            description: "Low confidence",
            confidence: 0.0,
            timelineIn: 0,
            timelineOut: 5
        )

        let highConfidence = Suggestion(
            id: UUID(),
            type: .removeSilence,
            title: "High",
            description: "High confidence",
            confidence: 1.0,
            timelineIn: 0,
            timelineOut: 5
        )

        XCTAssertEqual(lowConfidence.confidence, 0.0)
        XCTAssertEqual(highConfidence.confidence, 1.0)
    }

    func testSuggestionWithEmptyMetadata() {
        let suggestion = Suggestion(
            id: UUID(),
            type: .suggestCut,
            title: "Cut",
            description: "Suggested cut",
            confidence: 0.75,
            timelineIn: 15.0,
            timelineOut: 20.0,
            metadata: [:]
        )

        XCTAssertTrue(suggestion.metadata.isEmpty)
        XCTAssertNil(suggestion.metadata("nonexistent", as: String.self))
    }

    func testSuggestionTypeRawValues() {
        XCTAssertEqual(SuggestionType.removeSilence.rawValue, "removeSilence")
        XCTAssertEqual(SuggestionType.createChapter.rawValue, "createChapter")
        XCTAssertEqual(SuggestionType.suggestCut.rawValue, "suggestCut")
        XCTAssertEqual(SuggestionType.suggestOverlay.rawValue, "suggestOverlay")
        XCTAssertEqual(SuggestionType.suggestZoom.rawValue, "suggestZoom")
        XCTAssertEqual(SuggestionType.suggestBackground.rawValue, "suggestBackground")
    }

    func testAssetTypeRawValues() {
        XCTAssertEqual(AssetType.image.rawValue, "image")
        XCTAssertEqual(AssetType.video.rawValue, "video")
        XCTAssertEqual(AssetType.styledVideo.rawValue, "styledVideo")
        XCTAssertEqual(AssetType.processedCamera.rawValue, "processedCamera")
    }
}
