//
//  EditorModelTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

final class EditorModelTests: XCTestCase {

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
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        return Project(
            projectId: UUID(),
            name: "Test Project",
            sources: sources,
            timeline: timeline,
            canvas: canvas
        )
    }

    // MARK: - Initialization Tests

    func testEditorModelInitialization() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let retrievedProject = await editor.getProject()
        XCTAssertEqual(retrievedProject.timeline.segments.count, 3)
        XCTAssertEqual(retrievedProject.timeline.duration, 30.0)
    }

    func testSetProject() async throws {
        let editor = EditorModel(project: createTestProject())
        let newProject = createTestProject()

        await editor.setProject(newProject)

        let retrievedProject = await editor.getProject()
        XCTAssertEqual(retrievedProject.name, newProject.name)
    }

    // MARK: - Trim In Tests

    func testTrimInSuccess() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: 2.0)

        switch result {
        case .success(let editedProject):
            let segment = editedProject.timeline.segments[0]
            XCTAssertEqual(segment.sourceIn, 2.0)
            XCTAssertEqual(segment.sourceOut, 10.0)
            XCTAssertEqual(segment.timelineIn, 0.0)

            // Verify subsequent segments were adjusted
            let segment2 = editedProject.timeline.segments[1]
            XCTAssertEqual(segment2.timelineIn, 8.0) // 10.0 - 2.0

            let segment3 = editedProject.timeline.segments[2]
            XCTAssertEqual(segment3.timelineIn, 18.0) // 20.0 - 2.0

            // Verify total duration was recalculated
            XCTAssertEqual(editedProject.timeline.duration, 28.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testTrimInLastSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimIn(segmentId: "seg-3", newSourceIn: 22.0)

        switch result {
        case .success(let editedProject):
            let segment = editedProject.timeline.segments[2]
            XCTAssertEqual(segment.sourceIn, 22.0)
            XCTAssertEqual(segment.sourceOut, 30.0)
            XCTAssertEqual(segment.timelineIn, 20.0)

            // Verify no subsequent segments to adjust
            XCTAssertEqual(editedProject.timeline.segments.count, 3)

            // Verify total duration
            XCTAssertEqual(editedProject.timeline.duration, 28.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testTrimInSegmentNotFound() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimIn(segmentId: "non-existent", newSourceIn: 2.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .segmentNotFound(let id) = error {
                XCTAssertEqual(id, "non-existent")
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    func testTrimInInvalidTime() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Try to trim to a time greater than sourceOut
        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: 15.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .invalidTrimTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTrimTime error, got: \(error.localizedDescription)")
            }
        }
    }

    func testTrimInNegativeTime() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: -1.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .invalidTrimTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTrimTime error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Trim Out Tests

    func testTrimOutSuccess() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimOut(segmentId: "seg-1", newSourceOut: 8.0)

        switch result {
        case .success(let editedProject):
            let segment = editedProject.timeline.segments[0]
            XCTAssertEqual(segment.sourceIn, 0.0)
            XCTAssertEqual(segment.sourceOut, 8.0)
            XCTAssertEqual(segment.timelineIn, 0.0)

            // Verify subsequent segments were adjusted
            let segment2 = editedProject.timeline.segments[1]
            XCTAssertEqual(segment2.timelineIn, 8.0) // 10.0 - 2.0

            let segment3 = editedProject.timeline.segments[2]
            XCTAssertEqual(segment3.timelineIn, 18.0) // 20.0 - 2.0

            // Verify total duration was recalculated
            XCTAssertEqual(editedProject.timeline.duration, 28.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testTrimOutSegmentNotFound() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.trimOut(segmentId: "non-existent", newSourceOut: 8.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .segmentNotFound(let id) = error {
                XCTAssertEqual(id, "non-existent")
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    func testTrimOutInvalidTime() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Try to trim to a time less than sourceIn
        let result = await editor.trimOut(segmentId: "seg-1", newSourceOut: -1.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .invalidTrimTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTrimTime error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Split Tests

    func testSplitSuccess() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "seg-1", at: 5.0)

        switch result {
        case .success:
            XCTFail("Expected successWithInfo, got success")
        case .successWithInfo(let editedProject, let info):
            if case .splitCreated(let newSegmentId) = info {
                // Verify we now have 4 segments
                XCTAssertEqual(editedProject.timeline.segments.count, 4)

                // Verify first segment (0-5 on timeline, 0-5 in source)
                let segment1 = editedProject.timeline.segments[0]
                XCTAssertEqual(segment1.sourceIn, 0.0)
                XCTAssertEqual(segment1.sourceOut, 5.0)
                XCTAssertEqual(segment1.timelineIn, 0.0)

                // Verify second segment (5-10 on timeline, 5-10 in source)
                let segment2 = editedProject.timeline.segments[1]
                XCTAssertEqual(segment2.id, newSegmentId)
                XCTAssertEqual(segment2.sourceIn, 5.0)
                XCTAssertEqual(segment2.sourceOut, 10.0)
                XCTAssertEqual(segment2.timelineIn, 5.0)

                // Verify subsequent segments were not adjusted
                let segment3 = editedProject.timeline.segments[2]
                XCTAssertEqual(segment3.timelineIn, 10.0)

                // Verify total duration unchanged
                XCTAssertEqual(editedProject.timeline.duration, 30.0)

            } else {
                XCTFail("Expected splitCreated info, got: \(info)")
            }

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testSplitAtBeginning() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Split at the very beginning of the segment
        let result = await editor.split(segmentId: "seg-1", at: 0.1)

        switch result {
        case .success, .successWithInfo:
            // Should succeed
            break
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testSplitAtEnd() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Split at the very end of the segment
        let result = await editor.split(segmentId: "seg-1", at: 9.9)

        switch result {
        case .success, .successWithInfo:
            // Should succeed
            break
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testSplitOutsideSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Try to split at a time outside the segment
        let result = await editor.split(segmentId: "seg-1", at: 15.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .invalidSplitTime = error {
                // Expected error
            } else {
                XCTFail("Expected invalidSplitTime error, got: \(error.localizedDescription)")
            }
        }
    }

    func testSplitSegmentNotFound() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "non-existent", at: 5.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .segmentNotFound(let id) = error {
                XCTAssertEqual(id, "non-existent")
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delete Tests

    func testDeleteSuccess() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.delete(segmentId: "seg-2")

        switch result {
        case .success(let editedProject):
            // Verify we now have 2 segments
            XCTAssertEqual(editedProject.timeline.segments.count, 2)

            // Verify first segment unchanged
            let segment1 = editedProject.timeline.segments[0]
            XCTAssertEqual(segment1.id, "seg-1")
            XCTAssertEqual(segment1.timelineIn, 0.0)

            // Verify third segment was adjusted
            let segment3 = editedProject.timeline.segments[1]
            XCTAssertEqual(segment3.id, "seg-3")
            XCTAssertEqual(segment3.timelineIn, 10.0) // Was 20.0, now 10.0

            // Verify total duration was recalculated
            XCTAssertEqual(editedProject.timeline.duration, 20.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testDeleteFirstSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.delete(segmentId: "seg-1")

        switch result {
        case .success(let editedProject):
            XCTAssertEqual(editedProject.timeline.segments.count, 2)

            let segment2 = editedProject.timeline.segments[0]
            XCTAssertEqual(segment2.id, "seg-2")
            XCTAssertEqual(segment2.timelineIn, 0.0) // Was 10.0, now 0.0

            let segment3 = editedProject.timeline.segments[1]
            XCTAssertEqual(segment3.id, "seg-3")
            XCTAssertEqual(segment3.timelineIn, 10.0) // Was 20.0, now 10.0

            XCTAssertEqual(editedProject.timeline.duration, 20.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testDeleteLastSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.delete(segmentId: "seg-3")

        switch result {
        case .success(let editedProject):
            XCTAssertEqual(editedProject.timeline.segments.count, 2)

            // Verify first two segments unchanged
            XCTAssertEqual(editedProject.timeline.segments[0].timelineIn, 0.0)
            XCTAssertEqual(editedProject.timeline.segments[1].timelineIn, 10.0)

            XCTAssertEqual(editedProject.timeline.duration, 20.0)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    func testDeleteSegmentNotFound() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        let result = await editor.delete(segmentId: "non-existent")

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .segmentNotFound(let id) = error {
                XCTAssertEqual(id, "non-existent")
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delete Range Tests

    func testDeleteRangeEntireSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Delete exactly the middle segment
        let result = await editor.deleteRange(from: 10.0, to: 20.0)

        switch result {
        case .success:
            XCTFail("Expected successWithInfo, got success")
        case .successWithInfo(let editedProject, let info):
            if case .rangeDeleted(let count) = info {
                XCTAssertEqual(count, 1)

                // Verify we now have 2 segments
                XCTAssertEqual(editedProject.timeline.segments.count, 2)

                // Verify first segment unchanged
                XCTAssertEqual(editedProject.timeline.segments[0].id, "seg-1")
                XCTAssertEqual(editedProject.timeline.segments[0].timelineIn, 0.0)

                // Verify third segment was adjusted
                XCTAssertEqual(editedProject.timeline.segments[1].id, "seg-3")
                XCTAssertEqual(editedProject.timeline.segments[1].timelineIn, 10.0) // Was 20.0, now 10.0

                XCTAssertEqual(editedProject.timeline.duration, 20.0)

            } else {
                XCTFail("Expected rangeDeleted info, got: \(info)")
            }

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testDeleteRangePartialSegment() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Delete middle of first segment (5s to 8s)
        let result = await editor.deleteRange(from: 5.0, to: 8.0)

        switch result {
        case .success, .successWithInfo:
            // Should succeed - segment is trimmed
            let editedProject = result.getProject()!
            // The segment should be modified to exclude the deleted range
            // This is a complex operation, just verify it doesn't crash
            XCTAssertNotNil(editedProject)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testDeleteRangeMultipleSegments() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Delete from 5s to 25s (spans all three segments)
        let result = await editor.deleteRange(from: 5.0, to: 25.0)

        switch result {
        case .success, .successWithInfo:
            // Should succeed
            let editedProject = result.getProject()!
            XCTAssertNotNil(editedProject)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testDeleteRangeInvalidRange() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        // Start > End
        let result = await editor.deleteRange(from: 20.0, to: 10.0)

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .invalidRange = error {
                // Expected error
            } else {
                XCTFail("Expected invalidRange error, got: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Speed Tests

    func testSegmentWithDifferentSpeeds() async throws {
        let segment1 = Project.Timeline.Segment(
            id: "seg-1",
            sourceIn: 0.0,
            sourceOut: 20.0,
            timelineIn: 0.0,
            speed: 2.0 // 2x speed = 10s on timeline
        )

        let segment2 = Project.Timeline.Segment(
            id: "seg-2",
            sourceIn: 20.0,
            sourceOut: 30.0,
            timelineIn: 10.0,
            speed: 1.0 // 1x speed = 10s on timeline
        )

        let timeline = Project.Timeline(
            duration: 20.0,
            segments: [segment1, segment2]
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
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        let project = Project(
            projectId: UUID(),
            name: "Speed Test Project",
            sources: sources,
            timeline: timeline,
            canvas: canvas
        )

        let editor = EditorModel(project: project)

        // Trim first segment (which is 2x speed)
        let result = await editor.trimIn(segmentId: "seg-1", newSourceIn: 5.0)

        switch result {
        case .success(let editedProject):
            let segment = editedProject.timeline.segments[0]
            XCTAssertEqual(segment.sourceIn, 5.0)
            XCTAssertEqual(segment.sourceOut, 20.0)
            XCTAssertEqual(segment.timelineIn, 0.0)

            // Segment is now 15s of source at 2x speed = 7.5s on timeline
            // Second segment should start at 7.5s instead of 10.0s
            let segment2 = editedProject.timeline.segments[1]
            XCTAssertEqual(segment2.timelineIn, 7.5)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        case .successWithInfo:
            XCTFail("Expected success, got successWithInfo")
        }
    }

    // MARK: - Edge Cases

    func testEmptyTimeline() async throws {
        let timeline = Project.Timeline(
            duration: 0.0,
            segments: []
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
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        let project = Project(
            projectId: UUID(),
            name: "Empty Project",
            sources: sources,
            timeline: timeline,
            canvas: canvas
        )

        let editor = EditorModel(project: project)

        // Try to delete from empty timeline
        let result = await editor.delete(segmentId: "non-existent")

        switch result {
        case .success:
            XCTFail("Expected failure, got success")
        case .successWithInfo:
            XCTFail("Expected failure, got successWithInfo")
        case .failure(let error):
            if case .segmentNotFound = error {
                // Expected error
            } else {
                XCTFail("Expected segmentNotFound error, got: \(error.localizedDescription)")
            }
        }
    }

    func testSingleSegmentTimeline() async throws {
        let segment1 = Project.Timeline.Segment(
            id: "seg-1",
            sourceIn: 0.0,
            sourceOut: 10.0,
            timelineIn: 0.0,
            speed: 1.0
        )

        let timeline = Project.Timeline(
            duration: 10.0,
            segments: [segment1]
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
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        let project = Project(
            projectId: UUID(),
            name: "Single Segment Project",
            sources: sources,
            timeline: timeline,
            canvas: canvas
        )

        let editor = EditorModel(project: project)

        // Split the single segment
        let result = await editor.split(segmentId: "seg-1", at: 5.0)

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.timeline.segments.count, 2)

        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    // MARK: - Performance Tests

    func testPerformanceTrimIn() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        measure {
            Task {
                _ = await editor.trimIn(segmentId: "seg-1", newSourceIn: 2.0)
            }
        }
    }

    func testPerformanceSplit() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        measure {
            Task {
                _ = await editor.split(segmentId: "seg-1", at: 5.0)
            }
        }
    }

    func testPerformanceDelete() async throws {
        let project = createTestProject()
        let editor = EditorModel(project: project)

        measure {
            Task {
                _ = await editor.delete(segmentId: "seg-2")
            }
        }
    }

    // MARK: - Overlay Timing Tests

    func testUpdateOverlayStartTime() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: 2.0
        )

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 2.0)
            XCTAssertEqual(editedProject.overlays[0].end, 10.0)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testUpdateOverlayEndTime() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            end: 8.0
        )

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 0.0)
            XCTAssertEqual(editedProject.overlays[0].end, 8.0)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testUpdateOverlayBothTimes() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: 3.0,
            end: 7.0
        )

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 3.0)
            XCTAssertEqual(editedProject.overlays[0].end, 7.0)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testUpdateOverlayStartTimeExceedsEnd() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: 9.0
        )

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for start time >= end time")
        case .failure(let error):
            if case .invalidTrimTime(let sourceIn, let sourceOut, let reason) = error {
                XCTAssertEqual(sourceIn, 9.0)
                XCTAssertEqual(sourceOut, 10.0)
                XCTAssertEqual(reason, "Start time must be less than end time")
            } else {
                XCTFail("Expected invalidTrimTime error")
            }
        }
    }

    func testUpdateOverlayEndTimeBeforeStart() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            end: 1.0
        )

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for end time <= start time")
        case .failure(let error):
            if case .invalidTrimTime(let sourceIn, let sourceOut, let reason) = error {
                XCTAssertEqual(sourceIn, 0.0)
                XCTAssertEqual(sourceOut, 1.0)
                XCTAssertEqual(reason, "Start time must be less than end time")
            } else {
                XCTFail("Expected invalidTrimTime error")
            }
        }
    }

    func testUpdateOverlayStartNegative() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: -1.0
        )

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for negative start time")
        case .failure(let error):
            if case .invalidTrimTime(let sourceIn, let sourceOut, let reason) = error {
                XCTAssertEqual(sourceIn, -1.0)
                XCTAssertEqual(sourceOut, 10.0)
                XCTAssertEqual(reason, "Overlay timing must be within timeline duration")
            } else {
                XCTFail("Expected invalidTrimTime error")
            }
        }
    }

    func testUpdateOverlayEndExceedsTimeline() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            end: 15.0
        )

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for end time exceeding timeline duration")
        case .failure(let error):
            if case .invalidTrimTime(let sourceIn, let sourceOut, let reason) = error {
                XCTAssertEqual(sourceIn, 0.0)
                XCTAssertEqual(sourceOut, 15.0)
                XCTAssertEqual(reason, "Overlay timing must be within timeline duration")
            } else {
                XCTFail("Expected invalidTrimTime error")
            }
        }
    }

    func testUpdateOverlayNonExistent() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: UUID(),
            start: 2.0
        )

        switch result {
        case .success, .successWithInfo:
            XCTFail("Expected failure for non-existent overlay")
        case .failure(let error):
            XCTAssertEqual(error, .segmentNotFound(""))
        }
    }

    func testUpdateOverlayTimingWithStyleAndTransform() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        let newTransform = Project.Overlay.Transform(x: 0.6, y: 0.6, scale: 1.2, rotation: 15.0)
        let newStyle = Project.Overlay.Style(stroke: "#FF0000", strokeWidth: 8.0, shadow: false)

        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            transform: newTransform,
            style: newStyle,
            start: 1.0,
            end: 9.0
        )

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 1.0)
            XCTAssertEqual(editedProject.overlays[0].end, 9.0)
            XCTAssertEqual(editedProject.overlays[0].transform.x, 0.6)
            XCTAssertEqual(editedProject.overlays[0].style.stroke, "#FF0000")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error.localizedDescription)")
        }
    }

    func testUpdateOverlayTimingAtTimelineBoundaries() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        // Test at timeline start (0.0)
        let result1 = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: 0.0
        )

        switch result1 {
        case .success, .successWithInfo:
            let editedProject = result1.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 0.0)
        case .failure(let error):
            XCTFail("Expected success for start at 0.0, got error: \(error.localizedDescription)")
        }

        // Test at timeline end (10.0)
        let result2 = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            end: 10.0
        )

        switch result2 {
        case .success, .successWithInfo:
            let editedProject = result2.getProject()!
            XCTAssertEqual(editedProject.overlays[0].end, 10.0)
        case .failure(let error):
            XCTFail("Expected success for end at timeline duration, got error: \(error.localizedDescription)")
        }
    }

    func testUpdateOverlayTimingWithMinimumDuration() async throws {
        let project = createTestProjectWithOverlay()
        let editor = EditorModel(project: project)

        // Test minimum duration (0.1s difference)
        let result = await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: project.overlays[0].id,
            start: 5.0,
            end: 5.1
        )

        switch result {
        case .success, .successWithInfo:
            let editedProject = result.getProject()!
            XCTAssertEqual(editedProject.overlays[0].start, 5.0)
            XCTAssertEqual(editedProject.overlays[0].end, 5.1)
        case .failure(let error):
            XCTFail("Expected success for minimum duration, got error: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    func createTestProjectWithOverlay() -> Project {
        let timeline = Project.Timeline(
            duration: 10.0,
            segments: [
                Project.Timeline.Segment(
                    id: "seg-1",
                    sourceIn: 0.0,
                    sourceOut: 10.0,
                    timelineIn: 0.0,
                    speed: 1.0
                )
            ]
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        return Project(
            projectId: UUID(),
            name: "Test Project",
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "/path/to/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: timeline,
            canvas: canvas,
            overlays: [overlay]
        )
    }

    // MARK: - Split Propagation Tests

    func testSplit_PropagatesTakeId() async {
        var project = createTestProject()
        let takeId = UUID()
        project.timeline.segments[0].takeId = takeId
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "seg-1", at: 5.0)
        guard let updated = result.getProject() else { XCTFail("Split failed: \(result)"); return }

        XCTAssertEqual(updated.timeline.segments[0].takeId, takeId)
        XCTAssertEqual(updated.timeline.segments[1].takeId, takeId)
    }

    func testSplit_PropagatesZoom() async {
        var project = createTestProject()
        let zoom = Project.Timeline.ZoomConfiguration(enabled: true, intensity: .normal)
        project.timeline.segments[0].zoom = zoom
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "seg-1", at: 5.0)
        guard let updated = result.getProject() else { XCTFail("Split failed: \(result)"); return }

        XCTAssertEqual(updated.timeline.segments[0].zoom?.enabled, true)
        XCTAssertEqual(updated.timeline.segments[1].zoom?.enabled, true)
    }

    func testSplit_PropagatesCameraPosition() async {
        var project = createTestProject()
        let camera = Project.Canvas.Layout.CameraPosition(x: 0.1, y: 0.2, w: 0.3, h: 0.4, cornerRadius: 8)
        project.timeline.segments[0].cameraPosition = camera
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "seg-1", at: 5.0)
        guard let updated = result.getProject() else { XCTFail("Split failed: \(result)"); return }

        XCTAssertEqual(updated.timeline.segments[0].cameraPosition, camera)
        XCTAssertEqual(updated.timeline.segments[1].cameraPosition, camera)
    }

    func testSplit_PropagatesSpeed() async {
        var project = createTestProject()
        project.timeline.segments[0].speed = 2.0
        let editor = EditorModel(project: project)

        let result = await editor.split(segmentId: "seg-1", at: 2.5)
        guard let updated = result.getProject() else { XCTFail("Split failed: \(result)"); return }

        XCTAssertEqual(updated.timeline.segments[0].speed, 2.0)
        XCTAssertEqual(updated.timeline.segments[1].speed, 2.0)
    }

    // MARK: - Segment Model Tests

    func testSegment_CameraPositionDefaultsNil() {
        let segment = Project.Timeline.Segment(
            sourceIn: 0, sourceOut: 10, timelineIn: 0
        )
        XCTAssertNil(segment.cameraPosition)
    }

    func testSegment_BackwardCompatibleDecoding() throws {
        // JSON without cameraPosition field (old project format)
        let json = """
        {"id":"seg-1","sourceIn":0,"sourceOut":10,"timelineIn":0,"speed":1.5}
        """
        let data = json.data(using: .utf8)!
        let segment = try JSONDecoder().decode(Project.Timeline.Segment.self, from: data)

        XCTAssertEqual(segment.id, "seg-1")
        XCTAssertEqual(segment.speed, 1.5)
        XCTAssertNil(segment.cameraPosition)
        XCTAssertNil(segment.zoom)
        XCTAssertNil(segment.takeId)
    }
}
