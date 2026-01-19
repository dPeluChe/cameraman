//
//  TelemetrySyncTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class TelemetrySyncTests: XCTestCase {
    var sync: TelemetrySync!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        sync = TelemetrySync()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetrySyncTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        sync = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = TelemetrySync.Configuration.default

        XCTAssertEqual(config.acceptableDriftMs, 100.0)
        XCTAssertTrue(config.detectGaps)
        XCTAssertEqual(config.minGapDuration, 0.5)
        XCTAssertEqual(config.minExpectedEventsPerSecond, 10.0)
    }

    func testStrictConfiguration() {
        let config = TelemetrySync.Configuration.strict

        XCTAssertEqual(config.acceptableDriftMs, 50.0)
        XCTAssertTrue(config.detectGaps)
        XCTAssertEqual(config.minGapDuration, 0.1)
        XCTAssertEqual(config.minExpectedEventsPerSecond, 20.0)
    }

    func testLenientConfiguration() {
        let config = TelemetrySync.Configuration.lenient

        XCTAssertEqual(config.acceptableDriftMs, 200.0)
        XCTAssertFalse(config.detectGaps)
        XCTAssertEqual(config.minGapDuration, 1.0)
        XCTAssertEqual(config.minExpectedEventsPerSecond, 5.0)
    }

    func testCustomConfiguration() {
        let config = TelemetrySync.Configuration(
            acceptableDriftMs: 150.0,
            detectGaps: false,
            minGapDuration: 0.3,
            minExpectedEventsPerSecond: 15.0
        )

        XCTAssertEqual(config.acceptableDriftMs, 150.0)
        XCTAssertFalse(config.detectGaps)
        XCTAssertEqual(config.minGapDuration, 0.3)
        XCTAssertEqual(config.minExpectedEventsPerSecond, 15.0)
    }

    // MARK: - Telemetry File Loading Tests

    func testLoadValidTelemetryFile() async throws {
        let telemetryFile = createTelemetryFile(events: [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 150, y: 250),
            TelemetryRecorder.Event(t: 0.6, type: .up, x: 150, y: 250)
        ])

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: createSimpleTimeline(duration: 5.0)
        )

        XCTAssertEqual(result.stats.totalEvents, 3)
    }

    func testLoadEmptyTelemetryFile() async throws {
        let telemetryFile = createTelemetryFile(events: [])

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: createSimpleTimeline(duration: 5.0)
        )

        XCTAssertEqual(result.stats.totalEvents, 0)
        XCTAssertFalse(result.validation.isValid)
    }

    func testLoadNonExistentFile() async {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.jsonl")

        do {
            _ = try await sync.synchronize(
                telemetryFile: nonExistentFile,
                timeline: createSimpleTimeline(duration: 5.0)
            )
            XCTFail("Should throw error for non-existent file")
        } catch TelemetrySync.SyncError.fileNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testLoadMalformedTelemetryFile() async throws {
        let telemetryFile = tempDirectory.appendingPathComponent("malformed.jsonl")
        let malformedContent = """
        {"t":0.0,"type":"move","x":100,"y":200}
        this is not valid json
        {"t":0.5,"type":"down","button":0,"x":150,"y":250}
        """

        try malformedContent.write(to: telemetryFile, atomically: true, encoding: .utf8)

        // Should parse valid lines and skip invalid ones (or throw if all are invalid)
        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: createSimpleTimeline(duration: 5.0)
        )

        // Should have parsed the valid lines
        XCTAssertGreaterThan(result.stats.totalEvents, 0)
    }

    // MARK: - Timeline Synchronization Tests

    func testSyncWithSingleSegment() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 150, y: 250),
            TelemetryRecorder.Event(t: 2.0, type: .down, x: 200, y: 300)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 3)

        // First event should be at timeline time 0.0
        let firstEvent = result.events.first { $0.sourceTimestamp == 0.0 }
        XCTAssertNotNil(firstEvent)
        XCTAssertEqual(firstEvent?.timelineTimestamp, 0.0)
    }

    func testSyncWithMultipleSegments() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 100, y: 200),  // Segment 1
            TelemetryRecorder.Event(t: 1.5, type: .move, x: 150, y: 250),  // Segment 1
            TelemetryRecorder.Event(t: 5.0, type: .move, x: 200, y: 300),  // Segment 2 (gap: 2.0-4.0)
            TelemetryRecorder.Event(t: 6.0, type: .move, x: 250, y: 350)   // Segment 2
        ]

        let telemetryFile = createTelemetryFile(events: events)

        var timeline = Project.Timeline(
            duration: 10.0,
            segments: []
        )

        timeline.segments = [
            Project.Timeline.Segment(
                id: "seg-1",
                sourceIn: 0.0,
                sourceOut: 2.0,
                timelineIn: 0.0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: "seg-2",
                sourceIn: 4.0,
                sourceOut: 8.0,
                timelineIn: 2.0,
                speed: 1.0
            )
        ]

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 4)

        // Events in segment 1 should map to timeline 0.0-2.0
        let seg1Events = result.events.filter { $0.segmentId == "seg-1" }
        XCTAssertEqual(seg1Events.count, 2)

        // Events in segment 2 should map to timeline 2.0-6.0
        let seg2Events = result.events.filter { $0.segmentId == "seg-2" }
        XCTAssertEqual(seg2Events.count, 2)
    }

    func testSyncWithSegmentSpeed() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 150, y: 250),  // At 0.5x speed, this is at timeline 2.0
            TelemetryRecorder.Event(t: 2.0, type: .move, x: 200, y: 300)   // At 0.5x speed, this is at timeline 4.0
        ]

        let telemetryFile = createTelemetryFile(events: events)

        var timeline = Project.Timeline(
            duration: 10.0,
            segments: []
        )

        timeline.segments = [
            Project.Timeline.Segment(
                id: "seg-1",
                sourceIn: 0.0,
                sourceOut: 4.0,
                timelineIn: 0.0,
                speed: 0.5  // Half speed
            )
        ]

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 3)

        // Check that timeline timestamps are adjusted for speed
        let event1 = result.events.first { $0.sourceTimestamp == 1.0 }
        XCTAssertNotNil(event1)
        XCTAssertEqual(event1?.timelineTimestamp, 2.0, "Timeline timestamp should account for 0.5x speed")

        let event2 = result.events.first { $0.sourceTimestamp == 2.0 }
        XCTAssertNotNil(event2)
        XCTAssertEqual(event2?.timelineTimestamp, 4.0, "Timeline timestamp should account for 0.5x speed")
    }

    // MARK: - Validation Tests

    func testValidationWithValidSync() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 200, y: 300),
            TelemetryRecorder.Event(t: 1.1, type: .up, x: 200, y: 300)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertTrue(result.validation.isValid)
        XCTAssertEqual(result.validation.syncOffsetMs, 0.0, accuracy: 1.0)
        XCTAssertTrue(result.validation.drift == nil || !result.validation.drift!.isExcessive)
    }

    func testValidationWithLowEventCount() async throws {
        // Only 2 events over 5 seconds = 0.4 events/sec (below threshold of 10)
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 5.0, type: .move, x: 150, y: 250)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline,
            config: .default
        )

        // Should have warning about low event count
        let lowEventWarning = result.validation.warnings.first { $0.type == .lowEventCount }
        XCTAssertNotNil(lowEventWarning)
    }

    func testValidationWithMissingSegments() async throws {
        // Create events with a 1-second gap
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250),
            // Gap: 0.5 to 1.5 (1 second gap)
            TelemetryRecorder.Event(t: 1.5, type: .move, x: 200, y: 300),
            TelemetryRecorder.Event(t: 2.0, type: .move, x: 250, y: 350)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline,
            config: .default  // minGapDuration: 0.5
        )

        // Should detect the gap
        XCTAssertTrue(result.validation.missingSegments.contains { $0.duration >= 1.0 })
    }

    func testValidationWithUnbalancedClicks() async throws {
        // More downs than ups
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.1, type: .up, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 150, y: 250),
            TelemetryRecorder.Event(t: 0.6, type: .down, x: 200, y: 300)  // Extra down without up
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        // Should have warning about unbalanced clicks
        let clickWarning = result.validation.warnings.first { $0.type == .missingClickEvents }
        XCTAssertNotNil(clickWarning)
    }

    // MARK: - Statistics Tests

    func testStatisticsCalculation() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.1, type: .move, x: 150, y: 250),
            TelemetryRecorder.Event(t: 0.2, type: .move, x: 200, y: 300),
            TelemetryRecorder.Event(t: 0.3, type: .down, x: 250, y: 350),
            TelemetryRecorder.Event(t: 0.4, type: .up, x: 250, y: 350),
            TelemetryRecorder.Event(t: 0.5, type: .scroll, x: 300, y: 400, dx: 0.0, dy: -1.0)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 6)
        XCTAssertEqual(result.stats.moveEvents, 3)
        XCTAssertEqual(result.stats.clickEvents, 2)  // down + up
        XCTAssertEqual(result.stats.scrollEvents, 1)
        XCTAssertEqual(result.stats.eventsPerSecond, 6.0 / 5.0, accuracy: 0.1)
        XCTAssertEqual(result.stats.timeRange.lowerBound, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.stats.timeRange.upperBound, 0.5, accuracy: 0.01)
    }

    // MARK: - Debug Overlay Tests

    func testDebugOverlayCreation() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 200, y: 300),
            TelemetryRecorder.Event(t: 1.1, type: .up, x: 200, y: 300)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let syncResult = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        let overlay = await sync.createDebugOverlay(
            syncedEvents: syncResult.events,
            timeRange: 0.0...2.0
        )

        XCTAssertEqual(overlay.cursorPositions.count, 2)
        XCTAssertEqual(overlay.clickEvents.count, 2)
        XCTAssertEqual(overlay.timeRange.lowerBound, 0.0)
        XCTAssertEqual(overlay.timeRange.upperBound, 2.0)
    }

    func testDebugOverlayCursorPositionAtTimestamp() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 200, y: 400),
            TelemetryRecorder.Event(t: 2.0, type: .move, x: 300, y: 600)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let syncResult = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        let overlay = await sync.createDebugOverlay(
            syncedEvents: syncResult.events,
            timeRange: 0.0...3.0
        )

        // Test exact match
        let pos1 = overlay.cursorPosition(at: 0.0)
        XCTAssertNotNil(pos1)
        XCTAssertEqual(pos1?.x, 100)
        XCTAssertEqual(pos1?.y, 200)

        // Test interpolation
        let posInterpolated = overlay.cursorPosition(at: 0.5)
        XCTAssertNotNil(posInterpolated)
        XCTAssertEqual(posInterpolated?.x, 150, "Should interpolate between 100 and 200")
        XCTAssertEqual(posInterpolated?.y, 300, "Should interpolate between 200 and 400")

        // Test exact match at second point
        let pos2 = overlay.cursorPosition(at: 1.0)
        XCTAssertNotNil(pos2)
        XCTAssertEqual(pos2?.x, 200)
        XCTAssertEqual(pos2?.y, 400)
    }

    func testDebugOverlayClickEventsInRange() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.1, type: .up, x: 100, y: 200),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 200, y: 300),
            TelemetryRecorder.Event(t: 1.1, type: .up, x: 200, y: 300),
            TelemetryRecorder.Event(t: 2.0, type: .down, x: 300, y: 400),
            TelemetryRecorder.Event(t: 2.1, type: .up, x: 300, y: 400)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let syncResult = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        let overlay = await sync.createDebugOverlay(
            syncedEvents: syncResult.events,
            timeRange: 0.0...3.0
        )

        // Get click events in range 0.5-1.5
        let clicksInRange = overlay.clickEvents(in: 0.5...1.5)
        XCTAssertEqual(clicksInRange.count, 2)  // down and up at 1.0-1.1
    }

    // MARK: - Validation Standalone Tests

    func testValidateOnly() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 150, y: 250)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let validation = try await sync.validate(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertTrue(validation.isValid)
    }

    // MARK: - Edge Case Tests

    func testSyncWithAllEventTypes() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 150, y: 250, button: 0),
            TelemetryRecorder.Event(t: 0.6, type: .up, x: 150, y: 250, button: 0),
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 200, y: 300),
            TelemetryRecorder.Event(t: 1.5, type: .scroll, x: 250, y: 350, dx: 0.0, dy: -1.5),
            TelemetryRecorder.Event(t: 2.0, type: .down, x: 300, y: 400, button: 1),  // Right click
            TelemetryRecorder.Event(t: 2.1, type: .up, x: 300, y: 400, button: 1)
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 7)
        XCTAssertEqual(result.stats.moveEvents, 2)
        XCTAssertEqual(result.stats.clickEvents, 4)  // 2 downs + 2 ups
        XCTAssertEqual(result.stats.scrollEvents, 1)
    }

    func testSyncWithDisplayID() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200, displayID: "Main Display"),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250, displayID: "Secondary Display")
        ]

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 5.0)

        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )

        XCTAssertEqual(result.stats.totalEvents, 2)

        let overlay = await sync.createDebugOverlay(
            syncedEvents: result.events,
            timeRange: 0.0...1.0
        )

        XCTAssertEqual(overlay.cursorPositions.count, 2)
        XCTAssertEqual(overlay.cursorPositions[0].displayID, "Main Display")
        XCTAssertEqual(overlay.cursorPositions[1].displayID, "Secondary Display")
    }

    func testSyncPerformance() async throws {
        // Create a large number of events to test performance
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<1000 {
            let t = Double(i) * 0.016  // ~60 FPS
            events.append(TelemetryRecorder.Event(
                t: t,
                type: .move,
                x: Int(CGFloat(i) * 10) % 1920,
                y: Int(CGFloat(i) * 10) % 1080
            ))
        }

        let telemetryFile = createTelemetryFile(events: events)
        let timeline = createSimpleTimeline(duration: 20.0)

        let start = Date()
        let result = try await sync.synchronize(
            telemetryFile: telemetryFile,
            timeline: timeline
        )
        let duration = Date().timeIntervalSince(start)

        XCTAssertEqual(result.stats.totalEvents, 1000)
        XCTAssertLessThan(duration, 5.0, "Synchronization should complete in reasonable time")
    }

    // MARK: - Helper Methods

    private func createTelemetryFile(events: [TelemetryRecorder.Event]) -> URL {
        let fileURL = tempDirectory.appendingPathComponent("cursor.jsonl")
        var lines: [String] = []

        for event in events {
            if let jsonl = try? event.toJSONL() {
                lines.append(jsonl)
            }
        }

        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func createSimpleTimeline(duration: TimeInterval) -> Project.Timeline {
        var timeline = Project.Timeline(
            duration: duration,
            segments: []
        )

        timeline.segments = [
            Project.Timeline.Segment(
                id: "seg-1",
                sourceIn: 0.0,
                sourceOut: duration,
                timelineIn: 0.0,
                speed: 1.0
            )
        ]

        return timeline
    }
}
