//
//  ZoomPlanMergeTests.swift
//  EngineKitTests
//
//  Tests for merging manual zoom keyframes with auto-generated plans.
//

import XCTest
@testable import EngineKit

final class ZoomPlanMergeTests: XCTestCase {
    private let defaultConfig = ZoomPlanGenerator.Configuration.default()

    private func makeEvent(at start: TimeInterval, zoom: Double = 2.0) -> ZoomPlanGenerator.ZoomEvent {
        ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: start,
            zoomInEndTime: start + 0.5,
            holdEndTime: start + 1.5,
            zoomOutEndTime: start + 2.0,
            targetZoomLevel: zoom,
            focusX: 0.5,
            focusY: 0.5,
            clickWindowId: UUID()
        )
    }

    private func makePlan(events: [ZoomPlanGenerator.ZoomEvent]) -> ZoomPlanGenerator.ZoomPlan {
        let keyframes = events.flatMap { $0.generateKeyframes(defaultZoomLevel: defaultConfig.defaultZoomLevel) }
            .sorted { $0.timestamp < $1.timestamp }
        let stats = ZoomPlanGenerator.ZoomPlanStats(
            totalZoomEvents: events.count,
            totalKeyframes: keyframes.count,
            totalZoomedTime: 0,
            zoomedTimePercentage: 0,
            averageZoomLevel: 1,
            maximumZoomLevel: 1,
            averageTimeBetweenZooms: 0,
            zoomsPerMinute: 0,
            timeRange: 0...10
        )
        return ZoomPlanGenerator.ZoomPlan(
            events: events,
            keyframes: keyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }

    private func manualKeyframe(at t: TimeInterval, zoom: Double = 1.5, fx: Double = 0.3, fy: Double = 0.7) -> ZoomPlanGenerator.ZoomKeyframe {
        ZoomPlanGenerator.ZoomKeyframe(
            timestamp: t,
            zoomLevel: zoom,
            focusX: fx,
            focusY: fy,
            isManual: true
        )
    }

    // MARK: - Tests

    func testEmptyManualReturnsSamePlan() {
        let plan = makePlan(events: [makeEvent(at: 1.0)])
        let merged = plan.merged(with: [])
        XCTAssertEqual(merged.keyframes.count, plan.keyframes.count)
    }

    func testEmptyAutoReturnsManualOnly() {
        let plan = makePlan(events: [])
        let manual = [manualKeyframe(at: 2.0), manualKeyframe(at: 5.0)]
        let merged = plan.merged(with: manual)
        XCTAssertEqual(merged.keyframes.count, 2)
        XCTAssertTrue(merged.keyframes.allSatisfy { $0.isManual })
    }

    func testManualBeforeAutoIsPrepended() {
        let plan = makePlan(events: [makeEvent(at: 5.0)])
        let manual = [manualKeyframe(at: 1.0)]
        let merged = plan.merged(with: manual)
        XCTAssertEqual(merged.keyframes.first?.timestamp, 1.0)
        XCTAssertTrue(merged.keyframes.first?.isManual ?? false)
    }

    func testManualAfterAutoIsAppended() {
        let plan = makePlan(events: [makeEvent(at: 1.0)])
        let manual = [manualKeyframe(at: 10.0)]
        let merged = plan.merged(with: manual)
        XCTAssertEqual(merged.keyframes.last?.timestamp, 10.0)
        XCTAssertTrue(merged.keyframes.last?.isManual ?? false)
    }

    func testManualBetweenAutoKeyframesInsertsEcho() {
        // Auto event at t=1.0 generates keyframes at 1.0, 1.5, 2.5, 3.0
        let plan = makePlan(events: [makeEvent(at: 1.0)])
        let manual = [manualKeyframe(at: 2.0)]
        let merged = plan.merged(with: manual)

        // Should have: auto(1.0), auto(1.5), echo(~2.0), manual(2.0), auto(2.5), auto(3.0)
        let manualKf = merged.keyframes.first { $0.isManual }
        XCTAssertNotNil(manualKf)
        XCTAssertEqual(manualKf?.timestamp, 2.0)

        // There should be an echo keyframe just before the manual one
        let echoIdx = merged.keyframes.firstIndex { $0.isManual }
        XCTAssertNotNil(echoIdx)
        if let idx = echoIdx, idx > 0 {
            let echo = merged.keyframes[idx - 1]
            XCTAssertFalse(echo.isManual)
            XCTAssertLessThan(echo.timestamp, 2.0)
            XCTAssertGreaterThan(echo.timestamp, 1.5)
        }
    }

    func testMergedPlanZoomLevelRespectsManual() {
        let plan = makePlan(events: [makeEvent(at: 1.0, zoom: 2.0)])
        let manual = [manualKeyframe(at: 2.0, zoom: 3.0)]
        let merged = plan.merged(with: manual)

        // At the manual keyframe timestamp, zoom should be 3.0
        let zoomAtManual = merged.zoomLevel(at: 2.0)
        XCTAssertEqual(zoomAtManual, 3.0, accuracy: 0.01)
    }

    func testMergedPlanFocusRespectsManual() {
        let plan = makePlan(events: [makeEvent(at: 1.0)])
        let manual = [manualKeyframe(at: 2.0, fx: 0.25, fy: 0.75)]
        let merged = plan.merged(with: manual)

        let focus = merged.focusPoint(at: 2.0)
        XCTAssertEqual(focus.x, 0.25, accuracy: 0.01)
        XCTAssertEqual(focus.y, 0.75, accuracy: 0.01)
    }

    func testMultipleManualKeyframesMergeInOrder() {
        let plan = makePlan(events: [makeEvent(at: 1.0), makeEvent(at: 6.0)])
        let manual = [manualKeyframe(at: 4.0), manualKeyframe(at: 2.0)]
        let merged = plan.merged(with: manual)

        let manualTimestamps = merged.keyframes.filter { $0.isManual }.map { $0.timestamp }
        XCTAssertEqual(manualTimestamps, [2.0, 4.0])
    }
}
