//
//  TranscriptionViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit

@MainActor
final class TranscriptionViewTests: XCTestCase {
    var mockProject: Project!
    var mockProjectId: ProjectId!

    override func setUp() async throws {
        mockProjectId = UUID()

        // Create a mock project with audio source
        mockProject = Project(
            schemaVersion: 1,
            projectId: mockProjectId,
            name: "Test Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.MediaTrack(
                    id: "screen",
                    path: "screen.mov",
                    size: Project.VideoSize(width: 1920, height: 1080),
                    duration: 60.0,
                    frameRate: 30.0
                ),
                camera: nil,
                audio: Project.Sources.Audio(
                    mic: Project.MediaTrack(
                        id: "mic",
                        path: "mic.m4a",
                        size: Project.VideoSize(width: 0, height: 0),
                        duration: 60.0,
                        frameRate: 0.0
                    ),
                    system: nil
                ),
                telemetry: nil
            ),
            timeline: Project.Timeline(
                duration: 60.0,
                segments: []
            ),
            canvas: Project.Canvas(
                format: CanvasLayout.AspectRatio.r1690,
                layout: CanvasLayout.defaultLayout(for: .fullscreen),
                background: CanvasLayout.defaultBackground(for: .solid)
            ),
            overlays: [],
            captions: nil
        )
    }

    // MARK: - TranscriptionViewModel Tests

    func testTranscriptionViewModelInitialization() {
        let viewModel = TranscriptionViewModel()

        XCTAssertEqual(viewModel.transcriptionState, .notStarted)
        XCTAssertEqual(viewModel.transcriptionProgress, 0)
        XCTAssertTrue(viewModel.editedTexts.isEmpty)
        XCTAssertNil(viewModel.selectedSegmentId)
        XCTAssertNil(viewModel.editingSegmentId)
        XCTAssertFalse(viewModel.burnInCaptions)
    }

    func testTranscriptionViewModelStateTransitions() {
        let viewModel = TranscriptionViewModel()

        // Initial state
        XCTAssertEqual(viewModel.transcriptionState, .notStarted)

        // Simulate state changes
        viewModel.transcriptionState = .inProgress
        XCTAssertEqual(viewModel.transcriptionState, .inProgress)

        viewModel.transcriptionState = .completed
        XCTAssertEqual(viewModel.transcriptionState, .completed)

        viewModel.transcriptionState = .failed
        XCTAssertEqual(viewModel.transcriptionState, .failed)
    }

    func testTranscriptionViewModelProgressUpdates() {
        let viewModel = TranscriptionViewModel()

        viewModel.transcriptionProgress = 0.25
        XCTAssertEqual(viewModel.transcriptionProgress, 0.25)

        viewModel.transcriptionProgress = 0.5
        XCTAssertEqual(viewModel.transcriptionProgress, 0.5)

        viewModel.transcriptionProgress = 1.0
        XCTAssertEqual(viewModel.transcriptionProgress, 1.0)
    }

    func testTranscriptionViewModelSegmentEditing() {
        let viewModel = TranscriptionViewModel()

        // Create mock segments
        let segment1 = TranscriptionEngine.Transcript.Segment(
            id: 0,
            start: 0.0,
            end: 3.2,
            text: "Hello world"
        )
        let segment2 = TranscriptionEngine.Transcript.Segment(
            id: 1,
            start: 3.2,
            end: 6.8,
            text: "Testing transcription"
        )

        // Start editing segment
        viewModel.startEditing(segment: segment1)
        XCTAssertEqual(viewModel.editingSegmentId, 0)
        XCTAssertEqual(viewModel.selectedSegmentId, 0)
        XCTAssertEqual(viewModel.editedTexts[0], "Hello world")

        // Update text
        viewModel.updateSegmentText(segmentId: 0, text: "Hello world updated")
        XCTAssertEqual(viewModel.editedTexts[0], "Hello world updated")

        // Finish editing
        viewModel.finishEditing()
        XCTAssertNil(viewModel.editingSegmentId)
        XCTAssertNotNil(viewModel.editedTexts[0])

        // Start editing another segment
        viewModel.startEditing(segment: segment2)
        XCTAssertEqual(viewModel.editingSegmentId, 1)

        // Cancel editing
        viewModel.cancelEditing()
        XCTAssertNil(viewModel.editingSegmentId)
        XCTAssertNil(viewModel.editedTexts[1])
        XCTAssertNotNil(viewModel.editedTexts[0]) // First edit preserved
    }

    func testTranscriptionViewModelTextRetrieval() {
        let viewModel = TranscriptionViewModel()

        let segment = TranscriptionEngine.Transcript.Segment(
            id: 0,
            start: 0.0,
            end: 3.2,
            text: "Original text"
        )

        // Initially, edited text equals original
        XCTAssertEqual(viewModel.editedText(for: segment), "Original text")

        // After editing, returns edited text
        viewModel.editedTexts[0] = "Edited text"
        XCTAssertEqual(viewModel.editedText(for: segment), "Edited text")

        // For unedited segments, returns original
        let segment2 = TranscriptionEngine.Transcript.Segment(
            id: 1,
            start: 3.2,
            end: 6.8,
            text: "Another segment"
        )
        XCTAssertEqual(viewModel.editedText(for: segment2), "Another segment")
    }

    func testTranscriptionViewModelLanguageSelection() {
        let viewModel = TranscriptionViewModel()

        XCTAssertNil(viewModel.selectedLanguage)

        viewModel.selectedLanguage = "en"
        XCTAssertEqual(viewModel.selectedLanguage, "en")

        viewModel.selectedLanguage = "es"
        XCTAssertEqual(viewModel.selectedLanguage, "es")

        viewModel.selectedLanguage = nil
        XCTAssertNil(viewModel.selectedLanguage)
    }

    func testTranscriptionViewModelBurnInToggle() {
        let viewModel = TranscriptionViewModel()

        XCTAssertFalse(viewModel.burnInCaptions)

        viewModel.burnInCaptions = true
        XCTAssertTrue(viewModel.burnInCaptions)

        viewModel.burnInCaptions = false
        XCTAssertFalse(viewModel.burnInCaptions)
    }

    // MARK: - SRT Parsing Tests

    func testParseSRTBasic() {
        let viewModel = TranscriptionViewModel()
        let srtContent = """
        1
        00:00:00,000 --> 00:00:03,200
        Hello world

        2
        00:00:03,200 --> 00:00:06,800
        Testing transcription
        """

        let segments = viewModel.parseSRT(srtContent)

        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0].id, 0)
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 3.2)
        XCTAssertEqual(segments[0].text, "Hello world")

        XCTAssertEqual(segments[1].id, 1)
        XCTAssertEqual(segments[1].start, 3.2)
        XCTAssertEqual(segments[1].end, 6.8)
        XCTAssertEqual(segments[1].text, "Testing transcription")
    }

    func testParseSRTMultiLine() {
        let viewModel = TranscriptionViewModel()
        let srtContent = """
        1
        00:00:00,000 --> 00:00:03,200
        First line
        Second line

        2
        00:00:03,200 --> 00:00:06,800
        Another segment
        With multiple lines
        """

        let segments = viewModel.parseSRT(srtContent)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "First line\nSecond line")
        XCTAssertEqual(segments[1].text, "Another segment\nWith multiple lines")
    }

    func testParseSRTTimeParsing() {
        let viewModel = TranscriptionViewModel()

        XCTAssertEqual(viewModel.parseSRTTime("00:00:00,000"), 0.0)
        XCTAssertEqual(viewModel.parseSRTTime("00:00:01,500"), 1.5)
        XCTAssertEqual(viewModel.parseSRTTime("00:01:00,000"), 60.0)
        XCTAssertEqual(viewModel.parseSRTTime("01:00:00,000"), 3600.0)
        XCTAssertEqual(viewModel.parseSRTTime("01:23:45,678"), 5025.678)
    }

    func testParseSRTEmpty() {
        let viewModel = TranscriptionViewModel()
        let segments = viewModel.parseSRT("")
        XCTAssertTrue(segments.isEmpty)
    }

    func testParseSRTInvalid() {
        let viewModel = TranscriptionViewModel()
        let invalidSRT = """
        Invalid content
        without proper format
        """

        let segments = viewModel.parseSRT(invalidSRT)
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Transcript Model Tests

    func testTranscriptSegmentEquality() {
        let segment1 = TranscriptionEngine.Transcript.Segment(
            id: 0,
            start: 0.0,
            end: 3.2,
            text: "Hello"
        )
        let segment2 = TranscriptionEngine.Transcript.Segment(
            id: 0,
            start: 0.0,
            end: 3.2,
            text: "Hello"
        )
        let segment3 = TranscriptionEngine.Transcript.Segment(
            id: 1,
            start: 0.0,
            end: 3.2,
            text: "Hello"
        )

        XCTAssertEqual(segment1, segment2)
        XCTAssertNotEqual(segment1, segment3)
    }

    func testTranscriptCreation() {
        let segments = [
            TranscriptionEngine.Transcript.Segment(
                id: 0,
                start: 0.0,
                end: 3.2,
                text: "First"
            ),
            TranscriptionEngine.Transcript.Segment(
                id: 1,
                start: 3.2,
                end: 6.8,
                text: "Second"
            )
        ]

        let transcript = TranscriptionEngine.Transcript(
            language: "en",
            duration: 10.0,
            segments: segments
        )

        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.duration, 10.0)
        XCTAssertEqual(transcript.segments.count, 2)
        XCTAssertEqual(transcript.segments[0].text, "First")
        XCTAssertEqual(transcript.segments[1].text, "Second")
    }

    // MARK: - Integration Tests

    func testFullTranscriptionWorkflow() {
        let viewModel = TranscriptionViewModel()

        // Start with no state
        XCTAssertEqual(viewModel.transcriptionState, .notStarted)

        // Simulate transcription in progress
        viewModel.transcriptionState = .inProgress
        viewModel.transcriptionProgress = 0.5
        viewModel.progressMessage = "Transcribing..."

        XCTAssertEqual(viewModel.transcriptionState, .inProgress)
        XCTAssertEqual(viewModel.transcriptionProgress, 0.5)

        // Simulate completion
        let mockTranscript = TranscriptionEngine.Transcript(
            language: "en",
            duration: 60.0,
            segments: [
                TranscriptionEngine.Transcript.Segment(
                    id: 0,
                    start: 0.0,
                    end: 3.2,
                    text: "Welcome to the video"
                )
            ]
        )

        viewModel.transcript = mockTranscript
        viewModel.transcriptionState = .completed

        XCTAssertEqual(viewModel.transcriptionState, .completed)
        XCTAssertNotNil(viewModel.transcript)
        XCTAssertEqual(viewModel.transcript?.segments.count, 1)

        // Edit a segment
        let segment = mockTranscript.segments[0]
        viewModel.startEditing(segment: segment)
        viewModel.updateSegmentText(segmentId: 0, text: "Welcome to this awesome video")
        viewModel.finishEditing()

        XCTAssertEqual(viewModel.editedTexts[0], "Welcome to this awesome video")
    }

    func testMultipleSegmentsEditing() {
        let viewModel = TranscriptionViewModel()

        let transcript = TranscriptionEngine.Transcript(
            language: "en",
            duration: 60.0,
            segments: [
                TranscriptionEngine.Transcript.Segment(id: 0, start: 0.0, end: 3.0, text: "First"),
                TranscriptionEngine.Transcript.Segment(id: 1, start: 3.0, end: 6.0, text: "Second"),
                TranscriptionEngine.Transcript.Segment(id: 2, start: 6.0, end: 9.0, text: "Third")
            ]
        )

        viewModel.transcript = transcript

        // Edit first segment
        viewModel.startEditing(segment: transcript.segments[0])
        viewModel.updateSegmentText(segmentId: 0, text: "First updated")
        viewModel.finishEditing()

        // Edit second segment
        viewModel.startEditing(segment: transcript.segments[1])
        viewModel.updateSegmentText(segmentId: 1, text: "Second updated")
        viewModel.finishEditing()

        // Cancel editing third segment
        viewModel.startEditing(segment: transcript.segments[2])
        viewModel.updateSegmentText(segmentId: 2, text: "Third not saved")
        viewModel.cancelEditing()

        // Verify
        XCTAssertEqual(viewModel.editedText(for: transcript.segments[0]), "First updated")
        XCTAssertEqual(viewModel.editedText(for: transcript.segments[1]), "Second updated")
        XCTAssertEqual(viewModel.editedText(for: transcript.segments[2]), "Third") // Original text
    }

    func testSegmentSelection() {
        let viewModel = TranscriptionViewModel()

        let transcript = TranscriptionEngine.Transcript(
            language: "en",
            duration: 60.0,
            segments: [
                TranscriptionEngine.Transcript.Segment(id: 0, start: 0.0, end: 3.0, text: "First"),
                TranscriptionEngine.Transcript.Segment(id: 1, start: 3.0, end: 6.0, text: "Second"),
                TranscriptionEngine.Transcript.Segment(id: 2, start: 6.0, end: 9.0, text: "Third")
            ]
        )

        viewModel.transcript = transcript

        // Select segments
        viewModel.selectedSegmentId = 0
        XCTAssertEqual(viewModel.selectedSegmentId, 0)

        viewModel.selectedSegmentId = 1
        XCTAssertEqual(viewModel.selectedSegmentId, 1)

        viewModel.selectedSegmentId = nil
        XCTAssertNil(viewModel.selectedSegmentId)
    }

    // MARK: - Performance Tests

    func testSRTParsingPerformance() {
        let viewModel = TranscriptionViewModel()

        // Create a large SRT file
        var srtContent = ""
        for i in 0..<100 {
            let start = Double(i) * 3.0
            let end = start + 3.0
            srtContent += """
            \(i + 1)
            \(formatSRTTime(seconds: start)) --> \(formatSRTTime(seconds: end))
            Segment \(i + 1) text

            """
        }

        measure {
            _ = viewModel.parseSRT(srtContent)
        }
    }

    func testLargeTranscriptEditingPerformance() {
        let viewModel = TranscriptionViewModel()

        // Create a large transcript
        var segments: [TranscriptionEngine.Transcript.Segment] = []
        for i in 0..<1000 {
            segments.append(TranscriptionEngine.Transcript.Segment(
                id: i,
                start: Double(i) * 3.0,
                end: Double(i + 1) * 3.0,
                text: "Segment \(i + 1) text"
            ))
        }

        let transcript = TranscriptionEngine.Transcript(
            language: "en",
            duration: 3000.0,
            segments: segments
        )

        viewModel.transcript = transcript

        measure {
            // Simulate editing multiple segments
            for i in stride(from: 0, to: 100, by: 10) {
                viewModel.startEditing(segment: transcript.segments[i])
                viewModel.updateSegmentText(segmentId: i, text: "Edited segment \(i + 1)")
                viewModel.finishEditing()
            }
        }
    }

    // MARK: - Helper Functions

    private func formatSRTTime(seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }
}

// MARK: - Mock Extensions

extension TranscriptionViewModel {
    /// Expose parseSRTTime for testing
    func parseSRTTime(_ time: String) -> TimeInterval {
        let components = time.components(separatedBy: [:, .])
        guard components.count >= 4 else { return 0 }

        let hours = TimeInterval(components[0]) ?? 0
        let minutes = TimeInterval(components[1]) ?? 0
        let seconds = TimeInterval(components[2]) ?? 0
        let milliseconds = TimeInterval(components[3]) ?? 0

        return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
    }

    /// Expose parseSRT for testing
    func parseSRT(_ srt: String) -> [TranscriptionEngine.Transcript.Segment] {
        var segments: [TranscriptionEngine.Transcript.Segment] = []
        let blocks = srt.components(separatedBy: "\n\n").filter { !$0.isEmpty }

        for (index, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            let timestampLine = lines[1]
            let components = timestampLine.components(separatedBy: " --> ")
            guard components.count == 2 else { continue }

            let start = parseSRTTime(components[0])
            let end = parseSRTTime(components[1])
            let text = lines[2...].joined(separator: "\n")

            segments.append(TranscriptionEngine.Transcript.Segment(
                id: index,
                start: start,
                end: end,
                text: text
            ))
        }

        return segments
    }
}
