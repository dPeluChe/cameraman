//
//  ZoomPlanFilterTests.swift
//  EngineKitTests
//
//  Covers the per-segment filter that gates zoom application during preview/export.
//

import XCTest
@testable import EngineKit

final class ZoomPlanFilterTests: XCTestCase {
    private let defaultConfig = ZoomPlanGenerator.Configuration.default()

    // MARK: - Fixtures

    private func makeEvent(at start: TimeInterval, duration: TimeInterval = 2.0) -> ZoomPlanGenerator.ZoomEvent {
        ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: start,
            zoomInEndTime: start + 0.5,
            holdEndTime: start + 0.5 + duration,
            zoomOutEndTime: start + 0.5 + duration + 0.5,
            targetZoomLevel: 2.0,
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
            timeRange: 0...0
        )
        return ZoomPlanGenerator.ZoomPlan(
            events: events,
            keyframes: keyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }

    private func makeSegment(
        timelineIn: TimeInterval,
        timelineOut: TimeInterval,
        zoomEnabled: Bool?
    ) -> Project.Timeline.Segment {
        let zoom = zoomEnabled.map { Project.Timeline.ZoomConfiguration(enabled: $0) }
        // sourceOut - sourceIn determines duration; speed = 1 makes timelineDuration = source span.
        return Project.Timeline.Segment(
            sourceIn: 0,
            sourceOut: timelineOut - timelineIn,
            timelineIn: timelineIn,
            speed: 1.0,
            zoom: zoom
        )
    }

    // MARK: - Tests

    func testEmptySegmentsKeepsPlanIntact() {
        let plan = makePlan(events: [makeEvent(at: 1.0), makeEvent(at: 5.0)])
        let filtered = plan.filtered(byEnabledSegments: [])
        XCTAssertEqual(filtered.events.count, 2)
        XCTAssertEqual(filtered.keyframes.count, plan.keyframes.count)
    }

    func testDropsEventsInsideDisabledSegment() {
        let plan = makePlan(events: [makeEvent(at: 1.0), makeEvent(at: 5.0), makeEvent(at: 9.0)])
        let segments: [Project.Timeline.Segment] = [
            makeSegment(timelineIn: 0, timelineOut: 4, zoomEnabled: true),
            makeSegment(timelineIn: 4, timelineOut: 8, zoomEnabled: false),
            makeSegment(timelineIn: 8, timelineOut: 12, zoomEnabled: true)
        ]

        let filtered = plan.filtered(byEnabledSegments: segments)

        XCTAssertEqual(filtered.events.count, 2, "Event at 5.0 falls in the disabled segment and must be dropped")
        XCTAssertEqual(filtered.events.map(\.zoomInStartTime).sorted(), [1.0, 9.0])
    }

    func testNilZoomConfigCountsAsEnabled() {
        let plan = makePlan(events: [makeEvent(at: 2.0)])
        let segments: [Project.Timeline.Segment] = [
            makeSegment(timelineIn: 0, timelineOut: 5, zoomEnabled: nil)
        ]

        let filtered = plan.filtered(byEnabledSegments: segments)

        XCTAssertEqual(filtered.events.count, 1, "A segment with nil zoom config defaults to enabled")
    }

    func testAllSegmentsDisabledProducesNoZoomPlan() {
        let plan = makePlan(events: [makeEvent(at: 1.0), makeEvent(at: 5.0)])
        let segments: [Project.Timeline.Segment] = [
            makeSegment(timelineIn: 0, timelineOut: 4, zoomEnabled: false),
            makeSegment(timelineIn: 4, timelineOut: 8, zoomEnabled: false)
        ]

        let filtered = plan.filtered(byEnabledSegments: segments)

        XCTAssertTrue(filtered.events.isEmpty)
        XCTAssertTrue(filtered.keyframes.isEmpty)
        XCTAssertTrue(filtered.hasNoZoom)
    }

    func testKeyframesAreRegeneratedFromSurvivingEventsOnly() {
        let kept = makeEvent(at: 1.0)
        let dropped = makeEvent(at: 6.0)
        let plan = makePlan(events: [kept, dropped])
        let segments: [Project.Timeline.Segment] = [
            makeSegment(timelineIn: 0, timelineOut: 4, zoomEnabled: true),
            makeSegment(timelineIn: 4, timelineOut: 8, zoomEnabled: false)
        ]

        let filtered = plan.filtered(byEnabledSegments: segments)

        let keptKeyframeCount = kept.generateKeyframes(defaultZoomLevel: defaultConfig.defaultZoomLevel).count
        XCTAssertEqual(filtered.keyframes.count, keptKeyframeCount)
        XCTAssertTrue(filtered.keyframes.allSatisfy { $0.timestamp <= kept.zoomOutEndTime + 0.001 })
    }
}
