//
//  DwellDetectorTests.swift
//  EngineKitTests
//

import XCTest
@testable import EngineKit

final class DwellDetectorTests: XCTestCase {

    let config = DwellDetector.Configuration.default(screenWidth: 1920, screenHeight: 1080)

    // MARK: - Helper

    private func moveEvent(t: Double, x: Int, y: Int) -> TelemetryRecorder.Event {
        TelemetryRecorder.Event(t: t, type: .move, x: x, y: y)
    }

    // MARK: - Basic Detection

    func testDetectsSingleDwell() {
        // Cursor stays at (500, 300) for 1 second
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<60 {
            events.append(moveEvent(t: Double(i) / 60.0, x: 500, y: 300))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 1)

        let dwell = candidates[0]
        XCTAssertGreaterThanOrEqual(dwell.strength, config.minDwellDuration)
        XCTAssertLessThanOrEqual(dwell.strength, config.maxDwellDuration)
        XCTAssertEqual(dwell.focusX, 500.0 / 1920.0, accuracy: 0.01)
        XCTAssertEqual(dwell.focusY, 300.0 / 1080.0, accuracy: 0.01)
    }

    func testDetectsMultipleDwells() {
        var events: [TelemetryRecorder.Event] = []

        // Dwell 1: 0-1s at (100, 100)
        for i in 0..<60 {
            events.append(moveEvent(t: Double(i) / 60.0, x: 100, y: 100))
        }
        // Movement: 1-1.5s
        for i in 0..<30 {
            events.append(moveEvent(t: 1.0 + Double(i) / 60.0, x: 100 + i * 20, y: 100))
        }
        // Dwell 2: 1.5-2.5s at (800, 500)
        for i in 0..<60 {
            events.append(moveEvent(t: 1.5 + Double(i) / 60.0, x: 800, y: 500))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertLessThan(candidates[0].centerTime, candidates[1].centerTime)
    }

    func testIgnoresShortPauses() {
        // Cursor stays still for only 200ms (below 450ms threshold)
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<12 { // 12 frames at 60fps = 200ms
            events.append(moveEvent(t: Double(i) / 60.0, x: 500, y: 300))
        }
        // Then moves away
        events.append(moveEvent(t: 0.3, x: 1500, y: 800))

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 0)
    }

    func testIgnoresVeryLongPauses() {
        // Cursor stays still for 5 seconds (above 2.6s threshold — likely idle)
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<300 { // 5 seconds at 60fps
            events.append(moveEvent(t: Double(i) / 60.0, x: 500, y: 300))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 0)
    }

    // MARK: - Edge Cases

    func testEmptyEvents() {
        let candidates = DwellDetector.detect(events: [], config: config)
        XCTAssertEqual(candidates.count, 0)
    }

    func testSingleEvent() {
        let candidates = DwellDetector.detect(
            events: [moveEvent(t: 0, x: 500, y: 300)],
            config: config
        )
        XCTAssertEqual(candidates.count, 0)
    }

    func testAllMovement() {
        // Cursor constantly moving — no dwells
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<120 {
            events.append(moveEvent(t: Double(i) / 60.0, x: i * 16, y: i * 9))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 0)
    }

    func testFiltersNonMoveEvents() {
        // Only click events, no move events
        let events: [TelemetryRecorder.Event] = [
            TelemetryRecorder.Event(t: 0, type: .down, x: 500, y: 300, button: 0),
            TelemetryRecorder.Event(t: 0.5, type: .up, x: 500, y: 300, button: 0),
            TelemetryRecorder.Event(t: 1.0, type: .down, x: 500, y: 300, button: 0),
        ]

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 0)
    }

    // MARK: - Focus Normalization

    func testFocusNormalization() {
        // Dwell at screen center
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<60 {
            events.append(moveEvent(t: Double(i) / 60.0, x: 960, y: 540))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].focusX, 0.5, accuracy: 0.02)
        XCTAssertEqual(candidates[0].focusY, 0.5, accuracy: 0.02)
    }

    func testFocusClampsToZeroOne() {
        // Dwell at origin
        var events: [TelemetryRecorder.Event] = []
        for i in 0..<60 {
            events.append(moveEvent(t: Double(i) / 60.0, x: 0, y: 0))
        }

        let candidates = DwellDetector.detect(events: events, config: config)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertGreaterThanOrEqual(candidates[0].focusX, 0)
        XCTAssertGreaterThanOrEqual(candidates[0].focusY, 0)
        XCTAssertLessThanOrEqual(candidates[0].focusX, 1)
        XCTAssertLessThanOrEqual(candidates[0].focusY, 1)
    }
}
