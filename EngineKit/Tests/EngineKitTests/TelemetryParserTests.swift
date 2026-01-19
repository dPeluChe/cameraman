//
//  TelemetryParserTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class TelemetryParserTests: XCTestCase {
    var parser: TelemetryParser!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        parser = TelemetryParser()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryParserTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        parser = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = TelemetryParser.Configuration.default()

        XCTAssertEqual(config.timeWindowSize, 2.0)
        XCTAssertEqual(config.minClicksPerWindow, 2)
        XCTAssertEqual(config.maxClickInterval, 1.0)
        XCTAssertEqual(config.minMovementDistance, 50.0)
        XCTAssertTrue(config.includeLeftClicks)
        XCTAssertFalse(config.includeRightClicks)
        XCTAssertFalse(config.includeOtherClicks)
    }

    func testAggressiveConfiguration() {
        let config = TelemetryParser.Configuration.aggressive()

        XCTAssertEqual(config.timeWindowSize, 3.0)
        XCTAssertEqual(config.minClicksPerWindow, 1)
        XCTAssertEqual(config.maxClickInterval, 1.5)
        XCTAssertEqual(config.minMovementDistance, 30.0)
        XCTAssertTrue(config.includeLeftClicks)
        XCTAssertTrue(config.includeRightClicks)
        XCTAssertFalse(config.includeOtherClicks)
    }

    func testConservativeConfiguration() {
        let config = TelemetryParser.Configuration.conservative()

        XCTAssertEqual(config.timeWindowSize, 1.5)
        XCTAssertEqual(config.minClicksPerWindow, 3)
        XCTAssertEqual(config.maxClickInterval, 0.75)
        XCTAssertEqual(config.minMovementDistance, 80.0)
        XCTAssertTrue(config.includeLeftClicks)
        XCTAssertFalse(config.includeRightClicks)
        XCTAssertFalse(config.includeOtherClicks)
    }

    func testCustomConfiguration() {
        let config = TelemetryParser.Configuration(
            timeWindowSize: 5.0,
            minClicksPerWindow: 5,
            maxClickInterval: 2.0,
            minMovementDistance: 100.0,
            includeLeftClicks: false,
            includeRightClicks: true,
            includeOtherClicks: true
        )

        XCTAssertEqual(config.timeWindowSize, 5.0)
        XCTAssertEqual(config.minClicksPerWindow, 5)
        XCTAssertEqual(config.maxClickInterval, 2.0)
        XCTAssertEqual(config.minMovementDistance, 100.0)
        XCTAssertFalse(config.includeLeftClicks)
        XCTAssertTrue(config.includeRightClicks)
        XCTAssertTrue(config.includeOtherClicks)
    }

    // MARK: - BoundingBox Tests

    func testBoundingBoxCreation() {
        let bbox = TelemetryParser.BoundingBox(
            minX: 100,
            maxX: 300,
            minY: 200,
            maxY: 400
        )

        XCTAssertEqual(bbox.minX, 100)
        XCTAssertEqual(bbox.maxX, 300)
        XCTAssertEqual(bbox.minY, 200)
        XCTAssertEqual(bbox.maxY, 400)
        XCTAssertEqual(bbox.width, 200)
        XCTAssertEqual(bbox.height, 200)
    }

    func testBoundingBoxCenter() {
        let bbox = TelemetryParser.BoundingBox(
            minX: 100,
            maxX: 300,
            minY: 200,
            maxY: 400
        )

        XCTAssertEqual(bbox.center.x, 200)
        XCTAssertEqual(bbox.center.y, 300)
    }

    // MARK: - ImportantClick Tests

    func testImportantClickCreation() {
        let click = TelemetryParser.ImportantClick(
            timestamp: 1.5,
            x: 100,
            y: 200,
            button: 0,
            timeSincePreviousClick: 0.5,
            distanceFromPreviousClick: 60.0,
            windowId: UUID(),
            displayID: nil
        )

        XCTAssertEqual(click.timestamp, 1.5)
        XCTAssertEqual(click.x, 100)
        XCTAssertEqual(click.y, 200)
        XCTAssertEqual(click.button, 0)
        XCTAssertEqual(click.timeSincePreviousClick, 0.5)
        XCTAssertEqual(click.distanceFromPreviousClick, 60.0)
        XCTAssertNil(click.displayID)
    }

    // MARK: - ClickWindow Tests

    func testClickWindowCreation() {
        let clicks = [
            TelemetryParser.ImportantClick(
                timestamp: 1.0,
                x: 100,
                y: 200,
                button: 0,
                timeSincePreviousClick: 0,
                distanceFromPreviousClick: 0,
                windowId: UUID()
            ),
            TelemetryParser.ImportantClick(
                timestamp: 1.5,
                x: 150,
                y: 250,
                button: 0,
                timeSincePreviousClick: 0.5,
                distanceFromPreviousClick: 70.7,
                windowId: UUID()
            )
        ]

        let window = TelemetryParser.ClickWindow(
            startTime: 1.0,
            endTime: 1.5,
            clicks: clicks,
            centerPoint: CGPoint(x: 125, y: 225),
            boundingBox: TelemetryParser.BoundingBox(minX: 100, maxX: 150, minY: 200, maxY: 250),
            importanceScore: 50.0
        )

        XCTAssertEqual(window.startTime, 1.0)
        XCTAssertEqual(window.endTime, 1.5)
        XCTAssertEqual(window.duration, 0.5)
        XCTAssertEqual(window.clickCount, 2)
        XCTAssertEqual(window.importanceScore, 50.0)
        XCTAssertEqual(window.centerPoint.x, 125)
        XCTAssertEqual(window.centerPoint.y, 225)
    }

    // MARK: - Parse Events Tests

    func testParseEventsWithNoClicks() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250)
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.importantClicks.count, 0)
        XCTAssertEqual(result.windows.count, 0)
        XCTAssertEqual(result.stats.totalClicks, 0)
        XCTAssertEqual(result.stats.importantClickCount, 0)
    }

    func testParseEventsWithSingleClick() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0)
        ]

        let result = try await parser.parseEvents(events)

        // Single click doesn't meet minimum threshold (2 clicks per window)
        XCTAssertEqual(result.importantClicks.count, 1)
        XCTAssertEqual(result.windows.count, 0)
    }

    func testParseEventsWithMultipleClicks() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 0), // ~85px away
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 120, y: 220, button: 0)  // ~57px away
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.importantClicks.count, 3)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows.first?.clickCount, 3)
    }

    func testParseEventsWithMovementFiltering() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 110, y: 210, button: 0), // Only ~14px away
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 160, y: 260, button: 0)  // ~70px away
        ]

        let result = try await parser.parseEvents(events)

        // First click always included
        // Second click filtered out (too close)
        // Third click included (far enough from second)
        XCTAssertEqual(result.importantClicks.count, 2)
    }

    func testParseEventsWithTemporalWindows() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 0),
            // Gap of more than 2 seconds (default time window size)
            TelemetryRecorder.Event(t: 3.0, type: .down, x: 300, y: 400, button: 0),
            TelemetryRecorder.Event(t: 3.5, type: .down, x: 360, y: 460, button: 0)
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows[0].clickCount, 2)
        XCTAssertEqual(result.windows[1].clickCount, 2)
    }

    func testParseEventsWithRightClicksFiltered() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0), // Left click
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 1)  // Right click
        ]

        let result = try await parser.parseEvents(events)

        // Only left click included (right clicks filtered by default)
        XCTAssertEqual(result.importantClicks.count, 1)
        XCTAssertEqual(result.importantClicks.first?.button, 0)
    }

    func testParseEventsWithRightClicksIncluded() async throws {
        let config = TelemetryParser.Configuration(
            includeLeftClicks: true,
            includeRightClicks: true,
            includeOtherClicks: false
        )

        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0), // Left click
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 1)  // Right click
        ]

        let result = try await parser.parseEvents(events, config: config)

        XCTAssertEqual(result.importantClicks.count, 2)
    }

    // MARK: - Statistics Tests

    func testParseStatsWithNoClicks() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.5, type: .move, x: 150, y: 250)
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.stats.totalEvents, 2)
        XCTAssertEqual(result.stats.totalClicks, 0)
        XCTAssertEqual(result.stats.importantClickCount, 0)
        XCTAssertEqual(result.stats.windowCount, 0)
        XCTAssertEqual(result.stats.clicksPerSecond, 0)
    }

    func testParseStatsWithClicks() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 0),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 120, y: 220, button: 0)
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.stats.totalEvents, 3)
        XCTAssertEqual(result.stats.totalClicks, 3)
        XCTAssertEqual(result.stats.importantClickCount, 3)
        XCTAssertEqual(result.stats.windowCount, 1)
        XCTAssertEqual(result.stats.clicksPerSecond, 3.0, accuracy: 0.1)
    }

    func testParseStatsTimeRange() async throws {
        let events = [
            TelemetryRecorder.Event(t: 5.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 10.0, type: .down, x: 160, y: 260, button: 0)
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.stats.timeRange.lowerBound, 5.0, accuracy: 0.1)
        XCTAssertEqual(result.stats.timeRange.upperBound, 10.0, accuracy: 0.1)
    }

    // MARK: - File I/O Tests

    func testParseFromFile() async throws {
        // Create test telemetry file
        let telemetryFile = tempDirectory.appendingPathComponent("cursor.jsonl")
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 0),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 120, y: 220, button: 0)
        ]

        // Write events to file
        let lines = events.map { try? $0.toJSONL() }.compactMap { $0 }
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: telemetryFile, atomically: true, encoding: .utf8)

        // Parse file
        let result = try await parser.parse(telemetryFile: telemetryFile)

        XCTAssertEqual(result.importantClicks.count, 3)
        XCTAssertEqual(result.windows.count, 1)
    }

    func testParseFromNonExistentFile() async {
        let telemetryFile = tempDirectory.appendingPathComponent("nonexistent.jsonl")

        do {
            _ = try await parser.parse(telemetryFile: telemetryFile)
            XCTFail("Should have thrown error")
        } catch let error as TelemetryParser.ParserError {
            switch error {
            case .fileNotFound:
                // Expected
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testParseFromEmptyFile() async throws {
        let telemetryFile = tempDirectory.appendingPathComponent("empty.jsonl")
        try Data().write(to: telemetryFile)

        do {
            _ = try await parser.parse(telemetryFile: telemetryFile)
            XCTFail("Should have thrown error")
        } catch let error as TelemetryParser.ParserError {
            switch error {
            case .emptyFile:
                // Expected
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Edge Case Tests

    func testParseWithVeryCloseClicks() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.05, type: .down, x: 101, y: 201, button: 0), // Very close
            TelemetryRecorder.Event(t: 0.1, type: .down, x: 102, y: 202, button: 0)   // Very close
        ]

        let result = try await parser.parseEvents(events)

        // First click always included, others filtered by distance
        XCTAssertEqual(result.importantClicks.count, 1)
    }

    func testParseWithDisplayID() async throws {
        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0, displayID: "Display 1"),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 0, displayID: "Display 1")
        ]

        let result = try await parser.parseEvents(events)

        XCTAssertEqual(result.importantClicks.count, 2)
        XCTAssertEqual(result.importantClicks.first?.displayID, "Display 1")
        XCTAssertEqual(result.importantClicks.last?.displayID, "Display 1")
    }

    func testParseWithDifferentButtons() async throws {
        let config = TelemetryParser.Configuration(
            includeLeftClicks: true,
            includeRightClicks: true,
            includeOtherClicks: true
        )

        let events = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0), // Left
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 160, y: 260, button: 1), // Right
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 120, y: 220, button: 2)  // Middle
        ]

        let result = try await parser.parseEvents(events, config: config)

        XCTAssertEqual(result.importantClicks.count, 3)
        XCTAssertEqual(result.importantClicks[0].button, 0)
        XCTAssertEqual(result.importantClicks[1].button, 1)
        XCTAssertEqual(result.importantClicks[2].button, 2)
    }

    // MARK: - Performance Tests

    func testParsePerformanceWith100Events() async throws {
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<100 {
            let event = TelemetryRecorder.Event(
                t: Double(i) * 0.1,
                type: .down,
                x: 100 + i * 10,
                y: 200 + i * 10,
                button: 0
            )
            events.append(event)
        }

        let start = Date()
        _ = try await parser.parseEvents(events)
        let duration = Date().timeIntervalSince(start)

        // Should complete in reasonable time
        XCTAssertLessThan(duration, 1.0)
    }

    func testParsePerformanceWith1000Events() async throws {
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<1000 {
            let event = TelemetryRecorder.Event(
                t: Double(i) * 0.01,
                type: i % 2 == 0 ? .down : .move,
                x: 100 + i * 5,
                y: 200 + i * 5,
                button: 0
            )
            events.append(event)
        }

        let start = Date()
        _ = try await parser.parseEvents(events)
        let duration = Date().timeIntervalSince(start)

        // Should complete in reasonable time
        XCTAssertLessThan(duration, 2.0)
    }

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = TelemetryParser.Configuration.default()
                _ = TelemetryParser.Configuration.aggressive()
                _ = TelemetryParser.Configuration.conservative()
            }
        }
    }

    // MARK: - Window Importance Score Tests

    func testWindowImportanceScore() async throws {
        // Dense cluster of clicks (high importance)
        let denseEvents = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.1, type: .down, x: 110, y: 210, button: 0),
            TelemetryRecorder.Event(t: 0.2, type: .down, x: 105, y: 205, button: 0),
            TelemetryRecorder.Event(t: 0.3, type: .down, x: 108, y: 208, button: 0),
            TelemetryRecorder.Event(t: 0.4, type: .down, x: 102, y: 202, button: 0)
        ]

        let denseResult = try await parser.parseEvents(denseEvents)

        XCTAssertEqual(denseResult.windows.count, 1)
        XCTAssertGreaterThan(denseResult.windows.first!.importanceScore, 0)

        // Sparse cluster of clicks (lower importance)
        let sparseEvents = [
            TelemetryRecorder.Event(t: 0.0, type: .down, x: 100, y: 200, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .down, x: 500, y: 600, button: 0),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 1000, y: 200, button: 0)
        ]

        let sparseResult = try await parser.parseEvents(sparseEvents)

        XCTAssertEqual(sparseResult.windows.count, 1)
        XCTAssertGreaterThan(sparseResult.windows.first!.importanceScore, 0)
    }
}
