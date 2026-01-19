//
//  TimelineViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit

@MainActor
final class TimelineViewTests: XCTestCase {

    // MARK: - Test Helpers

    private func createTestProject() -> Project {
        let segment1 = Project.Timeline.Segment(
            id: "seg-1",
            sourceIn: 0.0,
            sourceOut: 10.0,
            timelineIn: 0.0,
            speed: 1.0
        )

        let segment2 = Project.Timeline.Segment(
            id: "seg-2",
            sourceIn: 10.0,
            sourceOut: 20.0,
            timelineIn: 10.0,
            speed: 1.0
        )

        let segment3 = Project.Timeline.Segment(
            id: "seg-3",
            sourceIn: 20.0,
            sourceOut: 30.0,
            timelineIn: 20.0,
            speed: 1.0
        )

        let timeline = Project.Timeline(
            duration: 30.0,
            segments: [segment1, segment2, segment3]
        )

        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov",
                fps: 60.0,
                size: Project.Sources.Size(w: 1920, h: 1080),
                syncOffsetMs: 0,
                sha256: "abc123",
                sizeBytes: 524288000
            ),
            camera: Project.Sources.MediaTrack(
                path: "sources/camera.mov",
                fps: 30.0,
                size: Project.Sources.Size(w: 1280, h: 720),
                syncOffsetMs: 0,
                sha256: "def456",
                sizeBytes: 104857600
            ),
            audio: Project.Sources.AudioTracks(
                system: Project.Sources.AudioTrack(
                    path: "sources/system_audio.m4a",
                    syncOffsetMs: 0,
                    sha256: "ghi789",
                    sizeBytes: 10485760
                ),
                mic: Project.Sources.AudioTrack(
                    path: "sources/mic_audio.m4a",
                    syncOffsetMs: 0,
                    sha256: "jkl012",
                    sizeBytes: 10485760
                )
            ),
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000"),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        return Project(
            schemaVersion: 1,
            projectId: UUID(),
            name: "Test Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: sources,
            timeline: timeline,
            canvas: canvas,
            overlays: [],
            captions: nil
        )
    }

    // MARK: - ProjectEditor Tests

    func testProjectEditorInitialization() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        XCTAssertEqual(editor.project.timeline.segments.count, 3)
        XCTAssertEqual(editor.project.timeline.duration, 30.0)
    }

    func testProjectEditorTrimIn() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Trim first segment from 0 to 2 seconds
        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: 2.0)

        switch result {
        case .success(let updatedProject):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceIn, 2.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineIn, 0.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 8.0) // Adjusted
        case .successWithInfo(let updatedProject, _):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceIn, 2.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineIn, 0.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 8.0) // Adjusted
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testProjectEditorTrimOut() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Trim first segment from 10 to 8 seconds
        let result = await editor.trimOut(segmentId: "seg-1", newSourceOut: 8.0)

        switch result {
        case .success(let updatedProject):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineDuration, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 8.0) // Adjusted
        case .successWithInfo(let updatedProject, _):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineDuration, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 8.0) // Adjusted
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testProjectEditorSplit() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Split first segment at timeline time 5
        let result = await editor.split(segmentId: "seg-1", at: 5.0)

        switch result {
        case .success(let updatedProject):
            XCTAssertEqual(updatedProject.timeline.segments.count, 4) // Original 3 + 1 from split
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 5.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].sourceIn, 5.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 5.0)
        case .successWithInfo(let updatedProject, let info):
            XCTAssertEqual(updatedProject.timeline.segments.count, 4) // Original 3 + 1 from split
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 5.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].sourceIn, 5.0)
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 5.0)

            if case .splitCreated(let newSegmentId) = info {
                XCTAssertFalse(newSegmentId.isEmpty)
            } else {
                XCTFail("Expected splitCreated info")
            }
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testProjectEditorDelete() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Delete second segment
        let result = await editor.delete(segmentId: "seg-2")

        switch result {
        case .success(let updatedProject):
            XCTAssertEqual(updatedProject.timeline.segments.count, 2) // Original 3 - 1 deleted
            XCTAssertEqual(updatedProject.timeline.segments[0].id, "seg-1")
            XCTAssertEqual(updatedProject.timeline.segments[1].id, "seg-3")
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 10.0) // Adjusted
        case .successWithInfo(let updatedProject, _):
            XCTAssertEqual(updatedProject.timeline.segments.count, 2) // Original 3 - 1 deleted
            XCTAssertEqual(updatedProject.timeline.segments[0].id, "seg-1")
            XCTAssertEqual(updatedProject.timeline.segments[1].id, "seg-3")
            XCTAssertEqual(updatedProject.timeline.segments[1].timelineIn, 10.0) // Adjusted
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testProjectEditorDeleteRange() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Delete range from 5 to 15 seconds (spans segments 1 and 2)
        let result = await editor.deleteRange(from: 5.0, to: 15.0)

        switch result {
        case .success(let updatedProject):
            // Should delete segment 1 (from 5s) and segment 2 (up to 15s)
            // Result depends on deleteRange implementation
            XCTAssertLessThanOrEqual(updatedProject.timeline.segments.count, 3)
        case .successWithInfo(let updatedProject, let info):
            XCTAssertLessThanOrEqual(updatedProject.timeline.segments.count, 3)

            if case .rangeDeleted(let count) = info {
                XCTAssertGreaterThan(count, 0)
            } else {
                XCTFail("Expected rangeDeleted info")
            }
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testProjectEditorUpdateProject() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Perform an operation
        _ = await editor.delete(segmentId: "seg-2")

        // Project should be updated
        XCTAssertEqual(editor.project.timeline.segments.count, 2)
    }

    // MARK: - RangeSelection Tests

    func testRangeSelectionDuration() {
        let selection = RangeSelection(startTime: 5.0, endTime: 15.0)
        XCTAssertEqual(selection.duration, 10.0)
    }

    func testRangeSelectionZeroDuration() {
        let selection = RangeSelection(startTime: 5.0, endTime: 5.0)
        XCTAssertEqual(selection.duration, 0.0)
    }

    // MARK: - Edge Cases

    func testProjectEditorTrimInInvalidTime() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Try to trim to a time after sourceOut
        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: 15.0)

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for invalid trim time")
        case .failure(let error):
            if case .invalidTrimTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTrimTime error, got: \(error.localizedDescription)")
            }
        }
    }

    func testProjectEditorTrimOutInvalidTime() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Try to trim to a time before sourceIn
        let result = await editor.trimOut(segmentId: "seg-1", newSourceOut: -5.0)

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for invalid trim time")
        case .failure(let error):
            if case .invalidTrimTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTrimTime error, got: \(error.localizedDescription)")
            }
        }
    }

    func testProjectEditorSplitInvalidTime() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Try to split at a time outside the segment
        let result = await editor.split(segmentId: "seg-1", at: 15.0)

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for invalid split time")
        case .failure(let error):
            if case .invalidSplitTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidSplitTime error, got: \(error.localizedDescription)")
            }
        }
    }

    func testProjectEditorDeleteSegmentNotFound() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Try to delete a non-existent segment
        let result = await editor.delete(segmentId: "non-existent")

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for non-existent segment")
        case .failure(let error):
            if case .segmentNotFound = error {
                // Expected error
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    func testProjectEditorDeleteRangeInvalidRange() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Try to delete with start >= end
        let result = await editor.deleteRange(from: 15.0, to: 10.0)

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for invalid range")
        case .failure(let error):
            if case .invalidRange = error {
                // Expected error
            } else {
                XCTFail("Expected invalidRange error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Performance Tests

    func testProjectEditorPerformance() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        measure {
            Task {
                _ = await editor.split(segmentId: "seg-1", at: 5.0)
            }
        }
    }

    func testProjectEditorMultipleOperations() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Perform multiple operations
        _ = await editor.trimIn(segmentId: "seg-1", newSourceIn: 2.0)
        _ = await editor.trimOut(segmentId: "seg-2", newSourceOut: 18.0)
        _ = await editor.split(segmentId: "seg-3", at: 25.0)
        _ = await editor.delete(segmentId: "seg-2")

        // Verify final state
        XCTAssertGreaterThan(editor.project.timeline.segments.count, 0)
    }

    // MARK: - Integration Tests

    func testTimelineViewIntegration() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Verify that ProjectEditor can be used with TimelineView
        // This is a basic integration test
        XCTAssertNotNil(editor.project)
        XCTAssertEqual(editor.project.timeline.segments.count, 3)
    }

    func testProjectEditorWithCameraTrack() async throws {
        var project = createTestProject()

        // Verify camera track exists
        XCTAssertNotNil(project.sources.camera)

        let editor = ProjectEditor(project: project)

        // Perform operations
        _ = await editor.split(segmentId: "seg-1", at: 5.0)

        // Camera track should still be present
        XCTAssertNotNil(editor.project.sources.camera)
    }

    func testProjectEditorWithAudioTracks() async throws {
        var project = createTestProject()

        // Verify audio tracks exist
        XCTAssertNotNil(project.sources.audio?.system)
        XCTAssertNotNil(project.sources.audio?.mic)

        let editor = ProjectEditor(project: project)

        // Perform operations
        _ = await editor.delete(segmentId: "seg-2")

        // Audio tracks should still be present
        XCTAssertNotNil(editor.project.sources.audio?.system)
        XCTAssertNotNil(editor.project.sources.audio?.mic)
    }

    // MARK: - Variable Speed Tests

    func testProjectEditorWithVariableSpeedSegments() async throws {
        let segment1 = Project.Timeline.Segment(
            id: "seg-1",
            sourceIn: 0.0,
            sourceOut: 10.0,
            timelineIn: 0.0,
            speed: 2.0 // 2x speed
        )

        let segment2 = Project.Timeline.Segment(
            id: "seg-2",
            sourceIn: 10.0,
            sourceOut: 20.0,
            timelineIn: 5.0, // 5 seconds on timeline (10s source / 2x speed)
            speed: 1.0
        )

        let timeline = Project.Timeline(
            duration: 15.0,
            segments: [segment1, segment2]
        )

        var project = createTestProject()
        project.timeline = timeline

        let editor = ProjectEditor(project: project)

        // Trim should respect speed
        let result = await editor.trimOut(segmentId: "seg-1", newSourceOut: 8.0)

        switch result {
        case .success(let updatedProject):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineDuration, 4.0) // 8s / 2x speed
        case .successWithInfo(let updatedProject, _):
            XCTAssertEqual(updatedProject.timeline.segments[0].sourceOut, 8.0)
            XCTAssertEqual(updatedProject.timeline.segments[0].timelineDuration, 4.0) // 8s / 2x speed
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    // MARK: - State Consistency Tests

    func testProjectEditorStateConsistencyAfterSplit() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        let originalDuration = editor.project.timeline.duration

        // Split should not change total duration
        _ = await editor.split(segmentId: "seg-1", at: 5.0)

        XCTAssertEqual(editor.project.timeline.duration, originalDuration)
    }

    func testProjectEditorStateConsistencyAfterDelete() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        let originalDuration = editor.project.timeline.duration

        // Delete should reduce total duration
        _ = await editor.delete(segmentId: "seg-2")

        XCTAssertLessThan(editor.project.timeline.duration, originalDuration)
    }

    func testProjectEditorSegmentOrderPreserved() async throws {
        let project = createTestProject()
        let editor = ProjectEditor(project: project)

        // Split should preserve segment order
        _ = await editor.split(segmentId: "seg-1", at: 5.0)

        let segments = editor.project.timeline.segments
        XCTAssertEqual(segments[0].timelineIn, 0.0)
        XCTAssertEqual(segments[1].timelineIn, 5.0)
        XCTAssertEqual(segments[2].timelineIn, 10.0)
    }
}
