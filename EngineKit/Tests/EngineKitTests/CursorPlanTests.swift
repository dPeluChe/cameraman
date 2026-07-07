//
//  CursorPlanTests.swift
//  EngineKit
//
//  Unit tests for CursorPlan interpolation and synthetic cursor rendering data.
//

import XCTest
@testable import EngineKit

final class CursorPlanTests: XCTestCase {

    func testPositionInterpolatesBetweenSamples() {
        let plan = CursorPlan(
            samples: [
                CursorSample(time: 0, x: 0, y: 0),
                CursorSample(time: 1, x: 1, y: 1)
            ],
            clicks: []
        )

        let pos = plan.position(at: 0.5)
        XCTAssertNotNil(pos)
        XCTAssertEqual(pos?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(pos?.y ?? -1, 0.5, accuracy: 0.001)
    }

    func testPositionClampsToFirstSampleBeforeStart() {
        let plan = CursorPlan(
            samples: [
                CursorSample(time: 1, x: 0.2, y: 0.3),
                CursorSample(time: 2, x: 0.4, y: 0.5)
            ],
            clicks: []
        )

        let pos = plan.position(at: 0)
        XCTAssertEqual(pos?.x ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(pos?.y ?? -1, 0.3, accuracy: 0.001)
    }

    func testPositionClampsToLastSampleAfterEnd() {
        let plan = CursorPlan(
            samples: [
                CursorSample(time: 0, x: 0.2, y: 0.3),
                CursorSample(time: 1, x: 0.4, y: 0.5)
            ],
            clicks: []
        )

        let pos = plan.position(at: 2)
        XCTAssertEqual(pos?.x ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(pos?.y ?? -1, 0.5, accuracy: 0.001)
    }

    func testActiveRipplesFiltersByDuration() {
        let plan = CursorPlan(
            samples: [],
            clicks: [
                CursorClickMark(time: 0, x: 0.5, y: 0.5),
                CursorClickMark(time: 10, x: 0.5, y: 0.5)
            ]
        )

        let ripples = plan.activeRipples(at: 0.2, rippleDuration: 0.5)
        XCTAssertEqual(ripples.count, 1)
        XCTAssertEqual(ripples.first?.age ?? -1, 0.4, accuracy: 0.001)

        let later = plan.activeRipples(at: 1.0, rippleDuration: 0.5)
        XCTAssertTrue(later.isEmpty)
    }

    func testGenerateFromEventsNormalizesCoordinates() {
        let events = [
            TelemetryRecorder.Event(t: 0, type: .move, x: 100, y: 200),
            TelemetryRecorder.Event(t: 0.1, type: .down, x: 200, y: 400)
        ]
        let plan = CursorPlanGenerator.generate(from: events, screenWidth: 400, screenHeight: 800)

        XCTAssertEqual(plan.samples.count, 2)
        XCTAssertEqual(plan.samples[0].x, 0.25, accuracy: 0.001)
        XCTAssertEqual(plan.samples[0].y, 0.25, accuracy: 0.001)
        XCTAssertEqual(plan.clicks.count, 1)
        XCTAssertEqual(plan.clicks[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(plan.clicks[0].y, 0.5, accuracy: 0.001)
    }

    func testGenerateEmptyWhenNoEvents() {
        let plan = CursorPlanGenerator.generate(from: [], screenWidth: 100, screenHeight: 100)
        XCTAssertTrue(plan.samples.isEmpty)
        XCTAssertTrue(plan.clicks.isEmpty)
    }
}
