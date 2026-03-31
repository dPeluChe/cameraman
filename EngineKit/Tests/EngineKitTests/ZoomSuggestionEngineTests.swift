//
//  ZoomSuggestionEngineTests.swift
//  EngineKitTests
//

import XCTest
@testable import EngineKit

final class ZoomSuggestionEngineTests: XCTestCase {

    // MARK: - Helpers

    private func moveEvent(t: Double, x: Int, y: Int) -> TelemetryRecorder.Event {
        TelemetryRecorder.Event(t: t, type: .move, x: x, y: y)
    }

    private func clickWindow(at time: TimeInterval, x: Int, y: Int, score: Double = 10) -> TelemetryParser.ClickWindow {
        TelemetryParser.ClickWindow(
            startTime: time,
            endTime: time + 0.3,
            clicks: [],
            centerPoint: CGPoint(x: CGFloat(x), y: CGFloat(y)),
            boundingBox: TelemetryParser.BoundingBox(minX: x - 20, maxX: x + 20, minY: y - 20, maxY: y + 20),
            importanceScore: score
        )
    }

    private func parseResult(windows: [TelemetryParser.ClickWindow]) -> TelemetryParser.ParseResult {
        TelemetryParser.ParseResult(
            importantClicks: [],
            windows: windows,
            stats: TelemetryParser.ParseStats(
                totalEvents: 100, totalClicks: windows.count,
                importantClickCount: windows.count, windowCount: windows.count,
                clicksPerSecond: 1, timeRange: 0...10
            )
        )
    }

    // MARK: - generateSuggestions

    func testCombinesClicksAndDwells() {
        // Click at t=1s
        let windows = [clickWindow(at: 1.0, x: 500, y: 300)]
        let result = parseResult(windows: windows)

        // Dwell events at t=5s (cursor stays still for 1s)
        var events: [TelemetryRecorder.Event] = []
        // Some initial movement
        for i in 0..<30 { events.append(moveEvent(t: Double(i) / 60.0, x: i * 20, y: 100)) }
        // Dwell at (800, 500) from t=4.5 to t=5.5
        for i in 0..<60 { events.append(moveEvent(t: 4.5 + Double(i) / 60.0, x: 800, y: 500)) }

        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: events,
            parseResult: result,
            screenWidth: 1920, screenHeight: 1080,
            timelineDuration: 10
        )

        XCTAssertGreaterThanOrEqual(suggestions.count, 1)

        let sources = Set(suggestions.map { $0.source })
        // Should have at least click source
        XCTAssertTrue(sources.contains(.click))
    }

    func testDeduplicatesNearbySuggestions() {
        // Two clicks very close in time (0.5s apart)
        let windows = [
            clickWindow(at: 2.0, x: 500, y: 300, score: 5),
            clickWindow(at: 2.3, x: 510, y: 310, score: 15),
        ]
        let result = parseResult(windows: windows)

        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: [],
            parseResult: result,
            screenWidth: 1920, screenHeight: 1080,
            timelineDuration: 10
        )

        // Should deduplicate to 1 (within 1.5s window), keeping higher score
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].score, 15)
    }

    func testKeepsSuggestionsFarApart() {
        let windows = [
            clickWindow(at: 1.0, x: 100, y: 100, score: 10),
            clickWindow(at: 5.0, x: 800, y: 500, score: 10),
        ]
        let result = parseResult(windows: windows)

        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: [],
            parseResult: result,
            screenWidth: 1920, screenHeight: 1080,
            timelineDuration: 10
        )

        XCTAssertEqual(suggestions.count, 2)
    }

    func testEmptyInputs() {
        let result = parseResult(windows: [])
        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: [],
            parseResult: result,
            screenWidth: 1920, screenHeight: 1080,
            timelineDuration: 10
        )

        XCTAssertEqual(suggestions.count, 0)
    }

    func testSortedByTime() {
        let windows = [
            clickWindow(at: 5.0, x: 800, y: 500),
            clickWindow(at: 1.0, x: 100, y: 100),
            clickWindow(at: 3.0, x: 400, y: 300),
        ]
        let result = parseResult(windows: windows)

        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: [],
            parseResult: result,
            screenWidth: 1920, screenHeight: 1080,
            timelineDuration: 10
        )

        for i in 1..<suggestions.count {
            XCTAssertGreaterThanOrEqual(suggestions[i].timelineTime, suggestions[i-1].timelineTime)
        }
    }

    // MARK: - ZoomSuggestion.toClickWindow

    func testToClickWindowConversion() {
        let suggestion = ZoomSuggestion(
            timelineTime: 3.5,
            focusX: 0.5,
            focusY: 0.5,
            zoomLevel: 2.0,
            source: .dwell,
            score: 8.0
        )

        let window = suggestion.toClickWindow(screenWidth: 1920, screenHeight: 1080)
        XCTAssertEqual(window.id, suggestion.id)
        XCTAssertEqual(window.startTime, 3.5)
        XCTAssertEqual(window.centerPoint.x, 960, accuracy: 1)
        XCTAssertEqual(window.centerPoint.y, 540, accuracy: 1)
        XCTAssertEqual(window.importanceScore, 8.0)
    }

    // MARK: - applyAsPlan

    func testApplyAsPlanGeneratesZoomPlan() async throws {
        let suggestions = [
            ZoomSuggestion(timelineTime: 2.0, focusX: 0.3, focusY: 0.4, zoomLevel: 2.0, source: .click, score: 10),
            ZoomSuggestion(timelineTime: 6.0, focusX: 0.7, focusY: 0.6, zoomLevel: 2.5, source: .dwell, score: 8),
        ]

        let plan = try await ZoomSuggestionEngine.applyAsPlan(
            suggestions: suggestions,
            timelineDuration: 10
        )

        XCTAssertGreaterThan(plan.events.count, 0)
        XCTAssertGreaterThan(plan.keyframes.count, 0)
    }

    func testApplyEmptySuggestionsThrows() async {
        do {
            _ = try await ZoomSuggestionEngine.applyAsPlan(
                suggestions: [],
                timelineDuration: 10
            )
            XCTFail("Should throw for empty suggestions")
        } catch {
            // Expected — ZoomPlanGenerator.noClickWindows
        }
    }
}
