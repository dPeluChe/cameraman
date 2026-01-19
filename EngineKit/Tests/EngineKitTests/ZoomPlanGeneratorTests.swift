//
//  ZoomPlanGeneratorTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Comprehensive test suite for ZoomPlanGenerator
/// Tests zoom plan generation, keyframe creation, easing functions, and configuration validation
final class ZoomPlanGeneratorTests: XCTestCase {
    var zoomPlanGenerator: ZoomPlanGenerator!

    override func setUp() {
        super.setUp()
        zoomPlanGenerator = ZoomPlanGenerator()
    }

    override func tearDown() {
        zoomPlanGenerator = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() async throws {
        let config = ZoomPlanGenerator.Configuration.default()

        XCTAssertEqual(config.minZoomLevel, 1.0)
        XCTAssertEqual(config.maxZoomLevel, 2.5)
        XCTAssertEqual(config.defaultZoomLevel, 1.0)
        XCTAssertEqual(config.zoomInDuration, 0.5)
        XCTAssertEqual(config.zoomOutDuration, 0.7)
        XCTAssertEqual(config.holdDuration, 1.0)
        XCTAssertEqual(config.boundingBoxPadding, 0.15)
        XCTAssertEqual(config.easingFunction, .easeInOut)
        XCTAssertEqual(config.maxZoomsPerMinute, 6)
        XCTAssertEqual(config.minTimeBetweenZooms, 3.0)
        XCTAssertTrue(config.zoomEnabled)

        // Should validate successfully
        try config.validate()
    }

    func testSubtleConfiguration() async throws {
        let config = ZoomPlanGenerator.Configuration.subtle()

        XCTAssertEqual(config.minZoomLevel, 1.0)
        XCTAssertEqual(config.maxZoomLevel, 1.8, "Subtle zoom should have lower max zoom")
        XCTAssertEqual(config.zoomInDuration, 0.8, "Subtle zoom should have slower zoom-in")
        XCTAssertEqual(config.zoomOutDuration, 1.0, "Subtle zoom should have slower zoom-out")
        XCTAssertEqual(config.holdDuration, 1.5, "Subtle zoom should have longer hold")
        XCTAssertEqual(config.maxZoomsPerMinute, 4, "Subtle zoom should have fewer zooms per minute")
        XCTAssertEqual(config.minTimeBetweenZooms, 5.0, "Subtle zoom should have more time between zooms")

        try config.validate()
    }

    func testAggressiveConfiguration() async throws {
        let config = ZoomPlanGenerator.Configuration.aggressive()

        XCTAssertEqual(config.minZoomLevel, 1.0)
        XCTAssertEqual(config.maxZoomLevel, 3.5, "Aggressive zoom should have higher max zoom")
        XCTAssertEqual(config.zoomInDuration, 0.3, "Aggressive zoom should have faster zoom-in")
        XCTAssertEqual(config.zoomOutDuration, 0.5, "Aggressive zoom should have faster zoom-out")
        XCTAssertEqual(config.holdDuration, 0.5, "Aggressive zoom should have shorter hold")
        XCTAssertEqual(config.maxZoomsPerMinute, 10, "Aggressive zoom should allow more zooms per minute")
        XCTAssertEqual(config.minTimeBetweenZooms, 2.0, "Aggressive zoom should have less time between zooms")

        try config.validate()
    }

    func testDisabledConfiguration() async throws {
        let config = ZoomPlanGenerator.Configuration.disabled()

        XCTAssertFalse(config.zoomEnabled, "Disabled configuration should have zoomEnabled = false")

        try config.validate()
    }

    func testCustomConfiguration() async throws {
        let config = ZoomPlanGenerator.Configuration(
            minZoomLevel: 1.2,
            maxZoomLevel: 3.0,
            defaultZoomLevel: 1.5,
            zoomInDuration: 0.6,
            zoomOutDuration: 0.8,
            holdDuration: 1.2,
            boundingBoxPadding: 0.2,
            easingFunction: .easeOutCubic,
            maxZoomsPerMinute: 8,
            minTimeBetweenZooms: 4.0,
            zoomEnabled: true
        )

        XCTAssertEqual(config.minZoomLevel, 1.2)
        XCTAssertEqual(config.maxZoomLevel, 3.0)
        XCTAssertEqual(config.defaultZoomLevel, 1.5)
        XCTAssertEqual(config.zoomInDuration, 0.6)
        XCTAssertEqual(config.zoomOutDuration, 0.8)
        XCTAssertEqual(config.holdDuration, 1.2)
        XCTAssertEqual(config.boundingBoxPadding, 0.2)
        XCTAssertEqual(config.easingFunction, .easeOutCubic)
        XCTAssertEqual(config.maxZoomsPerMinute, 8)
        XCTAssertEqual(config.minTimeBetweenZooms, 4.0)

        try config.validate()
    }

    func testConfigurationValidation_minZoomLevelTooLow() async {
        let config = ZoomPlanGenerator.Configuration(
            minZoomLevel: 0.5, // Invalid: must be >= 1.0
            maxZoomLevel: 2.5
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("minZoomLevel must be >= 1.0 (no zoom out)"))
        }
    }

    func testConfigurationValidation_maxZoomLevelExceedsMin() async {
        let config = ZoomPlanGenerator.Configuration(
            minZoomLevel: 2.5,
            maxZoomLevel: 2.0 // Invalid: must be > minZoomLevel
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("maxZoomLevel must be > minZoomLevel"))
        }
    }

    func testConfigurationValidation_maxZoomLevelTooHigh() async {
        let config = ZoomPlanGenerator.Configuration(
            minZoomLevel: 1.0,
            maxZoomLevel: 6.0 // Invalid: must be <= 5.0
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("maxZoomLevel must be <= 5.0 (5x zoom max to prevent disorientation)"))
        }
    }

    func testConfigurationValidation_defaultZoomLevelOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            minZoomLevel: 1.0,
            maxZoomLevel: 2.5,
            defaultZoomLevel: 3.0 // Invalid: must be between min and max
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("defaultZoomLevel must be between minZoomLevel and maxZoomLevel"))
        }
    }

    func testConfigurationValidation_zoomInDurationOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            zoomInDuration: 3.0 // Invalid: must be <= 2.0
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("zoomInDuration must be between 0 and 2 seconds"))
        }
    }

    func testConfigurationValidation_zoomOutDurationOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            zoomOutDuration: 0.0 // Invalid: must be > 0
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("zoomOutDuration must be between 0 and 2 seconds"))
        }
    }

    func testConfigurationValidation_holdDurationOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            holdDuration: 6.0 // Invalid: must be <= 5.0
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("holdDuration must be between 0 and 5 seconds"))
        }
    }

    func testConfigurationValidation_boundingBoxPaddingOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            boundingBoxPadding: 0.6 // Invalid: must be <= 0.5
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("boundingBoxPadding must be between 0 and 0.5 (50%)"))
        }
    }

    func testConfigurationValidation_maxZoomsPerMinuteOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            maxZoomsPerMinute: 25 // Invalid: must be <= 20
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("maxZoomsPerMinute must be between 1 and 20"))
        }
    }

    func testConfigurationValidation_minTimeBetweenZoomsOutOfRange() async {
        let config = ZoomPlanGenerator.Configuration(
            minTimeBetweenZooms: 15.0 // Invalid: must be <= 10.0
        )

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual((error as? ZoomPlanGenerator.ZoomPlanError), .invalidConfiguration("minTimeBetweenZooms must be between 1 and 10 seconds"))
        }
    }

    // MARK: - Easing Function Tests

    func testEasingFunction_linear() {
        let easing = ZoomPlanGenerator.EasingFunction.linear

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertEqual(easing.apply(to: 0.5), 0.5)
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeIn() {
        let easing = ZoomPlanGenerator.EasingFunction.easeIn

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertTrue(easing.apply(to: 0.5) < 0.5, "easeIn should start slow")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeOut() {
        let easing = ZoomPlanGenerator.EasingFunction.easeOut

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertTrue(easing.apply(to: 0.5) > 0.5, "easeOut should start fast")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeInOut() {
        let easing = ZoomPlanGenerator.EasingFunction.easeInOut

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertEqual(easing.apply(to: 0.5), 0.5, "easeInOut should be symmetric")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeInQuad() {
        let easing = ZoomPlanGenerator.EasingFunction.easeInQuad

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertEqual(easing.apply(to: 0.5), 0.25, "easeInQuad: t²")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeOutQuad() {
        let easing = ZoomPlanGenerator.EasingFunction.easeOutQuad

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertEqual(easing.apply(to: 0.5), 0.75, "easeOutQuad: t(2-t)")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_easeInOutCubic() {
        let easing = ZoomPlanGenerator.EasingFunction.easeInOutCubic

        XCTAssertEqual(easing.apply(to: 0.0), 0.0)
        XCTAssertEqual(easing.apply(to: 0.5), 0.5, "easeInOutCubic should be symmetric")
        XCTAssertEqual(easing.apply(to: 1.0), 1.0)
    }

    func testEasingFunction_clamping() {
        let easing = ZoomPlanGenerator.EasingFunction.easeInOut

        // Test clamping for values outside 0-1 range
        XCTAssertEqual(easing.apply(to: -0.5), 0.0, "Negative values should be clamped to 0")
        XCTAssertEqual(easing.apply(to: 1.5), 1.0, "Values > 1 should be clamped to 1")
    }

    // MARK: - ZoomKeyframe Tests

    func testZoomKeyframeInitialization() {
        let keyframe = ZoomPlanGenerator.ZoomKeyframe(
            timestamp: 10.0,
            zoomLevel: 2.0,
            focusX: 0.3,
            focusY: 0.7,
            easing: .easeOut
        )

        XCTAssertEqual(keyframe.timestamp, 10.0)
        XCTAssertEqual(keyframe.zoomLevel, 2.0)
        XCTAssertEqual(keyframe.focusX, 0.3)
        XCTAssertEqual(keyframe.focusY, 0.7)
        XCTAssertEqual(keyframe.easing, .easeOut)
    }

    func testZoomKeyframeDefaultEasing() {
        let keyframe = ZoomPlanGenerator.ZoomKeyframe(
            timestamp: 5.0,
            zoomLevel: 1.5,
            focusX: 0.5,
            focusY: 0.5
        )

        XCTAssertEqual(keyframe.easing, .easeInOut, "Default easing should be easeInOut")
    }

    // MARK: - ZoomEvent Tests

    func testZoomEventInitialization() {
        let zoomEvent = ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: 10.0,
            zoomInEndTime: 10.5,
            holdEndTime: 11.5,
            zoomOutEndTime: 12.2,
            targetZoomLevel: 2.0,
            focusX: 0.3,
            focusY: 0.7,
            clickWindowId: UUID(),
            easing: .easeInOut
        )

        XCTAssertEqual(zoomEvent.zoomInStartTime, 10.0)
        XCTAssertEqual(zoomEvent.zoomInEndTime, 10.5)
        XCTAssertEqual(zoomEvent.holdEndTime, 11.5)
        XCTAssertEqual(zoomEvent.zoomOutEndTime, 12.2)
        XCTAssertEqual(zoomEvent.targetZoomLevel, 2.0)
        XCTAssertEqual(zoomEvent.focusX, 0.3)
        XCTAssertEqual(zoomEvent.focusY, 0.7)
    }

    func testZoomEventDurations() {
        let zoomEvent = ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: 10.0,
            zoomInEndTime: 10.5,
            holdEndTime: 12.0,
            zoomOutEndTime: 12.7,
            targetZoomLevel: 2.0,
            focusX: 0.5,
            focusY: 0.5,
            clickWindowId: UUID()
        )

        XCTAssertEqual(zoomEvent.zoomInDuration, 0.5, accuracy: 0.01)
        XCTAssertEqual(zoomEvent.holdDuration, 1.5, accuracy: 0.01)
        XCTAssertEqual(zoomEvent.zoomOutDuration, 0.7, accuracy: 0.01)
        XCTAssertEqual(zoomEvent.totalDuration, 2.7, accuracy: 0.01)
    }

    func testZoomEventKeyframeGeneration() {
        let zoomEvent = ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: 10.0,
            zoomInEndTime: 10.5,
            holdEndTime: 11.5,
            zoomOutEndTime: 12.2,
            targetZoomLevel: 2.5,
            focusX: 0.3,
            focusY: 0.7,
            clickWindowId: UUID(),
            easing: .easeInOut
        )

        let keyframes = zoomEvent.generateKeyframes(defaultZoomLevel: 1.0)

        XCTAssertEqual(keyframes.count, 4, "Zoom event should generate 4 keyframes")

        // Keyframe 1: Start zoom-in
        XCTAssertEqual(keyframes[0].timestamp, 10.0)
        XCTAssertEqual(keyframes[0].zoomLevel, 1.0, "Should start at default zoom")
        XCTAssertEqual(keyframes[0].focusX, 0.5, "Should start at center")
        XCTAssertEqual(keyframes[0].focusY, 0.5, "Should start at center")

        // Keyframe 2: End zoom-in
        XCTAssertEqual(keyframes[1].timestamp, 10.5)
        XCTAssertEqual(keyframes[1].zoomLevel, 2.5, "Should reach target zoom")
        XCTAssertEqual(keyframes[1].focusX, 0.3, "Should focus on target point")
        XCTAssertEqual(keyframes[1].focusY, 0.7, "Should focus on target point")

        // Keyframe 3: End hold
        XCTAssertEqual(keyframes[2].timestamp, 11.5)
        XCTAssertEqual(keyframes[2].zoomLevel, 2.5, "Should maintain target zoom")
        XCTAssertEqual(keyframes[2].focusX, 0.3, "Should maintain focus")
        XCTAssertEqual(keyframes[2].focusY, 0.7, "Should maintain focus")

        // Keyframe 4: End zoom-out
        XCTAssertEqual(keyframes[3].timestamp, 12.2)
        XCTAssertEqual(keyframes[3].zoomLevel, 1.0, "Should return to default zoom")
        XCTAssertEqual(keyframes[3].focusX, 0.5, "Should return to center")
        XCTAssertEqual(keyframes[3].focusY, 0.5, "Should return to center")
    }

    // MARK: - ZoomPlan Tests

    func testGenerateZoomPlanFromParseResult() async throws {
        // Create mock parse result with click windows
        let clickWindow1 = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 5.0,
            endTime: 7.0,
            clicks: [
                TelemetryParser.ImportantClick(
                    timestamp: 5.5,
                    x: 500,
                    y: 300,
                    button: 0,
                    timeSincePreviousClick: 0,
                    distanceFromPreviousClick: 0,
                    windowId: UUID()
                )
            ],
            centerPoint: CGPoint(x: 500, y: 300),
            boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
            importanceScore: 10.0
        )

        let parseResult = TelemetryParser.ParseResult(
            importantClicks: [],
            windows: [clickWindow1],
            stats: TelemetryParser.ParseStats(
                totalEvents: 10,
                totalClicks: 5,
                importantClickCount: 5,
                windowCount: 1,
                clicksPerSecond: 1.0,
                timeRange: 0...10
            )
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: parseResult,
            config: config,
            timelineDuration: 30.0
        )

        XCTAssertFalse(zoomPlan.events.isEmpty, "Zoom plan should have events")
        XCTAssertFalse(zoomPlan.keyframes.isEmpty, "Zoom plan should have keyframes")
        XCTAssertEqual(zoomPlan.configuration, config)
        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 1)
    }

    func testGenerateZoomPlanFromClickWindows() async throws {
        let clickWindow1 = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 5.0,
            endTime: 7.0,
            clicks: [
                TelemetryParser.ImportantClick(
                    timestamp: 5.5,
                    x: 500,
                    y: 300,
                    button: 0,
                    timeSincePreviousClick: 0,
                    distanceFromPreviousClick: 0,
                    windowId: UUID()
                )
            ],
            centerPoint: CGPoint(x: 500, y: 300),
            boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow1],
            config: config,
            timelineDuration: 30.0
        )

        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 1)
        XCTAssertGreaterThan(zoomPlan.keyframes.count, 0)
    }

    func testGenerateZoomPlanDisabled() async throws {
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 5.0,
            endTime: 7.0,
            clicks: [],
            centerPoint: CGPoint(x: 500, y: 300),
            boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.disabled()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 0, "Disabled zoom should have no events")
        XCTAssertEqual(zoomPlan.stats.totalKeyframes, 0, "Disabled zoom should have no keyframes")
        XCTAssertEqual(zoomPlan.stats.averageZoomLevel, config.defaultZoomLevel)
    }

    func testGenerateZoomPlanNoClickWindows() async {
        let parseResult = TelemetryParser.ParseResult(
            importantClicks: [],
            windows: [],
            stats: TelemetryParser.ParseStats(
                totalEvents: 0,
                totalClicks: 0,
                importantClickCount: 0,
                windowCount: 0,
                clicksPerSecond: 0,
                timeRange: 0...0
            )
        )

        let config = ZoomPlanGenerator.Configuration.default()

        do {
            _ = try await zoomPlanGenerator.generateZoomPlan(
                from: parseResult,
                config: config,
                timelineDuration: 30.0
            )
            XCTFail("Should throw error for no click windows")
        } catch ZoomPlanGenerator.ZoomPlanError.noClickWindows {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateZoomPlanZoomRateExceeded() async {
        // Create many click windows to exceed zoom rate limit
        var clickWindows: [TelemetryParser.ClickWindow] = []
        for i in 0..<20 {
            let window = TelemetryParser.ClickWindow(
                id: UUID(),
                startTime: Double(i) * 2.0,
                endTime: Double(i) * 2.0 + 2.0,
                clicks: [],
                centerPoint: CGPoint(x: 500, y: 300),
                boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
                importanceScore: 10.0
            )
            clickWindows.append(window)
        }

        let config = ZoomPlanGenerator.Configuration.default()

        do {
            _ = try await zoomPlanGenerator.generateZoomPlan(
                from: clickWindows,
                config: config,
                timelineDuration: 30.0
            )
            XCTFail("Should throw error for zoom rate exceeded")
        } catch ZoomPlanGenerator.ZoomPlanError.zoomRateExceeded(let actual, let maximum) {
            XCTAssertTrue(actual > maximum, "Actual zoom rate should exceed maximum")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateZoomPlanMinTimeBetweenZooms() async throws {
        // Create two click windows close together (less than minTimeBetweenZooms)
        let clickWindow1 = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 5.0,
            endTime: 7.0,
            clicks: [],
            centerPoint: CGPoint(x: 500, y: 300),
            boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
            importanceScore: 10.0
        )

        let clickWindow2 = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 7.5, // Only 0.5s after first window ends (should be skipped)
            endTime: 9.5,
            clicks: [],
            centerPoint: CGPoint(x: 800, y: 600),
            boundingBox: TelemetryParser.BoundingBox(minX: 750, maxX: 850, minY: 550, maxY: 650),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration(
            minTimeBetweenZooms: 3.0 // Second window should be skipped
        )

        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow1, clickWindow2],
            config: config,
            timelineDuration: 30.0
        )

        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 1, "Second zoom event should be skipped due to minTimeBetweenZooms")
    }

    func testZoomPlanZoomLevelAtTimestamp() async throws {
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 10.0,
            endTime: 12.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 900, maxX: 1000, minY: 500, maxY: 600),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration(
            zoomInDuration: 0.5,
            zoomOutDuration: 0.5,
            holdDuration: 1.0
        )

        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        // Before zoom starts
        let zoomBefore = zoomPlan.zoomLevel(at: 5.0)
        XCTAssertEqual(zoomBefore, config.defaultZoomLevel, "Should be at default zoom before event starts")

        // During zoom-in (midpoint)
        let zoomDuringIn = zoomPlan.zoomLevel(at: 10.25)
        XCTAssertTrue(zoomDuringIn > config.defaultZoomLevel && zoomDuringIn < zoomPlan.events.first!.targetZoomLevel, "Should be interpolating during zoom-in")

        // During hold
        let zoomDuringHold = zoomPlan.zoomLevel(at: 11.0)
        XCTAssertEqual(zoomDuringHold, zoomPlan.events.first!.targetZoomLevel, accuracy: 0.01, "Should be at target zoom during hold")

        // After zoom ends
        let zoomAfter = zoomPlan.zoomLevel(at: 15.0)
        XCTAssertEqual(zoomAfter, config.defaultZoomLevel, "Should return to default zoom after event ends")
    }

    func testZoomPlanFocusPointAtTimestamp() async throws {
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 10.0,
            endTime: 12.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 900, maxX: 1000, minY: 500, maxY: 600),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        // During hold (should be focused on click window center)
        let focusDuringHold = zoomPlan.focusPoint(at: 11.0)
        XCTAssertTrue(abs(focusDuringHold.x - 0.5) < 0.1, "Focus X should be near center")
        XCTAssertTrue(abs(focusDuringHold.y - 0.5) < 0.1, "Focus Y should be near center")
    }

    // MARK: - ZoomPlanStats Tests

    func testZoomPlanStatsCalculation() async throws {
        // Create multiple click windows
        var clickWindows: [TelemetryParser.ClickWindow] = []
        for i in 0..<3 {
            let window = TelemetryParser.ClickWindow(
                id: UUID(),
                startTime: Double(i * 10) + 5.0,
                endTime: Double(i * 10) + 7.0,
                clicks: [],
                centerPoint: CGPoint(x: 500, y: 300),
                boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
                importanceScore: 10.0
            )
            clickWindows.append(window)
        }

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: clickWindows,
            config: config,
            timelineDuration: 60.0
        )

        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 3)
        XCTAssertGreaterThan(zoomPlan.stats.totalKeyframes, 0)
        XCTAssertGreaterThan(zoomPlan.stats.totalZoomedTime, 0)
        XCTAssertGreaterThan(zoomPlan.stats.zoomedTimePercentage, 0)
        XCTAssertGreaterThan(zoomPlan.stats.averageZoomLevel, config.defaultZoomLevel)
        XCTAssertGreaterThanOrEqual(zoomPlan.stats.maximumZoomLevel, zoomPlan.stats.averageZoomLevel)
        XCTAssertGreaterThan(zoomPlan.stats.zoomsPerMinute, 0)
        XCTAssertEqual(zoomPlan.stats.timeRange.upperBound, 60.0)
    }

    // MARK: - Performance Tests

    func testZoomPlanGenerationPerformance() async throws {
        // Create many click windows for performance testing
        var clickWindows: [TelemetryParser.ClickWindow] = []
        for i in 0..<50 {
            let window = TelemetryParser.ClickWindow(
                id: UUID(),
                startTime: Double(i) * 10.0,
                endTime: Double(i) * 10.0 + 2.0,
                clicks: [],
                centerPoint: CGPoint(x: 500, y: 300),
                boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
                importanceScore: Double.random(in: 5...15)
            )
            clickWindows.append(window)
        }

        let config = ZoomPlanGenerator.Configuration.default()
        let timelineDuration = 500.0

        measure {
            let group = DispatchGroup()
            group.enter()

            Task {
                _ = try? await zoomPlanGenerator.generateZoomPlan(
                    from: clickWindows,
                    config: config,
                    timelineDuration: timelineDuration
                )
                group.leave()
            }

            group.wait()
        }
    }

    func testZoomLevelInterpolationPerformance() async throws {
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 10.0,
            endTime: 12.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 900, maxX: 1000, minY: 500, maxY: 600),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        measure {
            for i in 0..<1000 {
                let timestamp = Double(i) * 0.03
                _ = zoomPlan.zoomLevel(at: timestamp)
            }
        }
    }

    // MARK: - Edge Cases

    func testZoomPlanWithVerySmallBoundingBox() async throws {
        // Very small bounding box should result in high zoom level
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 10.0,
            endTime: 12.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 955, maxX: 965, minY: 535, maxY: 545), // Only 10x10 pixels
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        // Small bounding box should result in high zoom level (close to max)
        XCTAssertGreaterThan(zoomPlan.events.first!.targetZoomLevel, config.minZoomLevel)
        XCTAssertLessThanOrEqual(zoomPlan.events.first!.targetZoomLevel, config.maxZoomLevel)
    }

    func testZoomPlanWithVeryLargeBoundingBox() async throws {
        // Very large bounding box should result in low zoom level
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 10.0,
            endTime: 12.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 100, maxX: 1800, minY: 100, maxY: 900), // Almost full screen
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 30.0
        )

        // Large bounding box should result in low zoom level (close to min)
        XCTAssertGreaterThanOrEqual(zoomPlan.events.first!.targetZoomLevel, config.minZoomLevel)
        XCTAssertLessThan(zoomPlan.events.first!.targetZoomLevel, config.maxZoomLevel)
    }

    func testZoomPlanWithZeroDurationTimeline() async throws {
        let clickWindow = TelemetryParser.ClickWindow(
            id: UUID(),
            startTime: 0.0,
            endTime: 2.0,
            clicks: [],
            centerPoint: CGPoint(x: 960, y: 540),
            boundingBox: TelemetryParser.BoundingBox(minX: 900, maxX: 1000, minY: 500, maxY: 600),
            importanceScore: 10.0
        )

        let config = ZoomPlanGenerator.Configuration.default()

        // Should not throw error for zero duration
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: [clickWindow],
            config: config,
            timelineDuration: 0.0
        )

        XCTAssertGreaterThan(zoomPlan.stats.totalZoomEvents, 0)
    }

    func testZoomPlanKeyframeSorting() async throws {
        // Create multiple click windows to test keyframe sorting
        var clickWindows: [TelemetryParser.ClickWindow] = []
        for i in 0..<5 {
            let window = TelemetryParser.ClickWindow(
                id: UUID(),
                startTime: Double(i) * 10.0,
                endTime: Double(i) * 10.0 + 2.0,
                clicks: [],
                centerPoint: CGPoint(x: 500, y: 300),
                boundingBox: TelemetryParser.BoundingBox(minX: 450, maxX: 550, minY: 250, maxY: 350),
                importanceScore: 10.0
            )
            clickWindows.append(window)
        }

        let config = ZoomPlanGenerator.Configuration.default()
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlan(
            from: clickWindows,
            config: config,
            timelineDuration: 60.0
        )

        // Verify keyframes are sorted by timestamp
        for i in 0..<(zoomPlan.keyframes.count - 1) {
            XCTAssertLessThanOrEqual(zoomPlan.keyframes[i].timestamp, zoomPlan.keyframes[i + 1].timestamp, "Keyframes should be sorted by timestamp")
        }
    }

    // MARK: - Per-Section Zoom Plan Generation Tests (Épica I, Task 4)

    func testGenerateZoomPlanWithSections_AllEnabled() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        // Create test segments with different zoom configurations
        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .subtle)
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            ),
            Project.Timeline.Segment(
                id: "segment-3",
                sourceIn: 20.0,
                sourceOut: 30.0,
                timelineIn: 20.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .aggressive)
            )
        ]

        // Create click windows spread across segments
        let clickWindows = createTestClickWindows(count: 9, duration: 30.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 30.0
        )

        // Assert
        XCTAssertGreaterThan(zoomPlan.events.count, 0, "Should generate zoom events")
        XCTAssertGreaterThan(zoomPlan.keyframes.count, 0, "Should generate keyframes")

        // Verify different zoom levels based on intensity
        let aggressiveEvents = zoomPlan.events.filter { $0.zoomInStartTime >= 20.0 }
        if !aggressiveEvents.isEmpty {
            let maxAggressiveZoom = aggressiveEvents.map { $0.targetZoomLevel }.max() ?? 0
            XCTAssertGreaterThanOrEqual(maxAggressiveZoom, 3.0, "Aggressive segment should have higher zoom levels")
        }

        let subtleEvents = zoomPlan.events.filter { $0.zoomInStartTime < 10.0 }
        if !subtleEvents.isEmpty {
            let maxSubtleZoom = subtleEvents.map { $0.targetZoomLevel }.max() ?? 0
            XCTAssertLessThan(maxSubtleZoom, 2.0, "Subtle segment should have lower zoom levels")
        }
    }

    func testGenerateZoomPlanWithSections_SomeDisabled() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration.disabled // Disabled
            ),
            Project.Timeline.Segment(
                id: "segment-3",
                sourceIn: 20.0,
                sourceOut: 30.0,
                timelineIn: 20.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            )
        ]

        let clickWindows = createTestClickWindows(count: 9, duration: 30.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 30.0
        )

        // Assert
        // No zoom events should be generated in segment-2 (disabled)
        let eventsInSegment2 = zoomPlan.events.filter { $0.zoomInStartTime >= 10.0 && $0.zoomInStartTime < 20.0 }
        XCTAssertEqual(eventsInSegment2.count, 0, "Should have no zoom events in disabled segment")

        // Zoom events should exist in segments 1 and 3
        let eventsInSegments1And3 = zoomPlan.events.filter { event in
            (event.zoomInStartTime >= 0.0 && event.zoomInStartTime < 10.0) ||
            (event.zoomInStartTime >= 20.0 && event.zoomInStartTime < 30.0)
        }
        XCTAssertGreaterThan(eventsInSegments1And3.count, 0, "Should have zoom events in enabled segments")
    }

    func testGenerateZoomPlanWithSections_AllDisabled() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration.disabled
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration.disabled
            ),
            Project.Timeline.Segment(
                id: "segment-3",
                sourceIn: 20.0,
                sourceOut: 30.0,
                timelineIn: 20.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration.disabled
            )
        ]

        let clickWindows = createTestClickWindows(count: 9, duration: 30.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 30.0
        )

        // Assert
        XCTAssertEqual(zoomPlan.events.count, 0, "Should have no zoom events when all segments are disabled")
        XCTAssertEqual(zoomPlan.keyframes.count, 0, "Should have no keyframes")
        XCTAssertEqual(zoomPlan.stats.totalZoomEvents, 0)
    }

    func testGenerateZoomPlanWithSections_NoExplicitConfiguration() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        // Segments with no explicit zoom configuration (will use defaults)
        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: nil // No explicit configuration
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: nil
            )
        ]

        let clickWindows = createTestClickWindows(count: 6, duration: 20.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 20.0
        )

        // Assert
        XCTAssertGreaterThan(zoomPlan.events.count, 0, "Should generate zoom events using default configuration")
        XCTAssertTrue(zoomPlan.configuration.zoomEnabled, "Should use default configuration with zoom enabled")
    }

    func testGenerateZoomPlanWithSections_CustomConfiguration() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        // Segment with custom min/max zoom levels
        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(
                    enabled: true,
                    minZoomLevel: 1.5,
                    maxZoomLevel: 4.0,
                    intensity: nil
                )
            )
        ]

        let clickWindows = createTestClickWindows(count: 3, duration: 10.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 10.0
        )

        // Assert
        XCTAssertGreaterThan(zoomPlan.events.count, 0)

        // Verify custom zoom levels are respected
        for event in zoomPlan.events {
            XCTAssertGreaterThanOrEqual(event.targetZoomLevel, 1.5, "Zoom level should be at least minZoomLevel")
            XCTAssertLessThanOrEqual(event.targetZoomLevel, 4.0, "Zoom level should be at most maxZoomLevel")
        }
    }

    func testGenerateZoomPlanWithSections_EmptyClickWindows() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            )
        ]

        let clickWindows: [TelemetryParser.ClickWindow] = []

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 10.0
        )

        // Assert
        XCTAssertEqual(zoomPlan.events.count, 0, "Should have no zoom events with no click windows")
        XCTAssertEqual(zoomPlan.keyframes.count, 0, "Should have no keyframes")
    }

    func testGenerateZoomPlanWithSections_SegmentFiltering() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        // Create click windows only in segment 1 (0-10s)
        let clickWindows = createTestClickWindows(count: 3, duration: 10.0)

        // Create segments spanning 0-30s
        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            ),
            Project.Timeline.Segment(
                id: "segment-3",
                sourceIn: 20.0,
                sourceOut: 30.0,
                timelineIn: 20.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            )
        ]

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 30.0
        )

        // Assert
        // All zoom events should be in segment 1
        for event in zoomPlan.events {
            XCTAssertGreaterThanOrEqual(event.zoomInStartTime, 0.0)
            XCTAssertLessThan(event.zoomInStartTime, 10.0, "All zoom events should be in segment 1")
        }

        // No zoom events should be in segments 2 and 3
        let eventsInSegment2 = zoomPlan.events.filter { $0.zoomInStartTime >= 10.0 && $0.zoomInStartTime < 20.0 }
        let eventsInSegment3 = zoomPlan.events.filter { $0.zoomInStartTime >= 20.0 && $0.zoomInStartTime < 30.0 }
        XCTAssertEqual(eventsInSegment2.count, 0, "Should have no zoom events in segment 2")
        XCTAssertEqual(eventsInSegment3.count, 0, "Should have no zoom events in segment 3")
    }

    func testGenerateZoomPlanWithSections_KeyframeOrdering() async throws {
        // Arrange
        let zoomPlanGenerator = ZoomPlanGenerator()

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0.0,
                sourceOut: 10.0,
                timelineIn: 0.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .normal)
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 10.0,
                sourceOut: 20.0,
                timelineIn: 10.0,
                speed: 1.0,
                zoom: Project.Timeline.ZoomConfiguration(intensity: .aggressive)
            )
        ]

        let clickWindows = createTestClickWindows(count: 6, duration: 20.0)

        // Act
        let zoomPlan = try await zoomPlanGenerator.generateZoomPlanWithSections(
            from: clickWindows,
            segments: segments,
            defaultConfig: .default(),
            timelineDuration: 20.0
        )

        // Assert
        // Verify keyframes are sorted by timestamp across all segments
        for i in 0..<(zoomPlan.keyframes.count - 1) {
            XCTAssertLessThanOrEqual(zoomPlan.keyframes[i].timestamp, zoomPlan.keyframes[i + 1].timestamp, "Keyframes should be sorted by timestamp across all segments")
        }
    }

    // MARK: - Helper Methods for Per-Section Tests

    func createTestClickWindows(count: Int, duration: TimeInterval) -> [TelemetryParser.ClickWindow] {
        var windows: [TelemetryParser.ClickWindow] = []
        let timeInterval = duration / Double(count)

        for i in 0..<count {
            let startTime = Double(i) * timeInterval
            let windowId = UUID()
            let click = TelemetryParser.ImportantClick(
                timestamp: startTime + timeInterval / 2,
                x: 100 + i * 10,
                y: 100 + i * 10,
                button: 0,
                timeSincePreviousClick: i > 0 ? timeInterval : 0,
                distanceFromPreviousClick: i > 0 ? 10.0 : 0,
                windowId: windowId,
                displayID: "main"
            )
            let boundingBox = TelemetryParser.BoundingBox(
                minX: 100 + i * 10 - 50,
                maxX: 100 + i * 10 + 50,
                minY: 100 + i * 10 - 50,
                maxY: 100 + i * 10 + 50
            )
            let centerPoint = CGPoint(x: 100.0 + Double(i * 10), y: 100.0 + Double(i * 10))
            let window = TelemetryParser.ClickWindow(
                id: windowId,
                startTime: startTime,
                endTime: startTime + timeInterval,
                clicks: [click],
                centerPoint: centerPoint,
                boundingBox: boundingBox,
                importanceScore: Double(count - i) / Double(count)
            )
            windows.append(window)
        }

        return windows
    }

    func createTestTelemetryEvents(count: Int, duration: TimeInterval) -> [TelemetryRecorder.Event] {
        var events: [TelemetryRecorder.Event] = []
        let timeInterval = duration / Double(count)

        for i in 0..<count {
            let timestamp = Double(i) * timeInterval

            if i % 3 == 0 {
                // Click event
                let event = TelemetryRecorder.Event(
                    t: timestamp,
                    type: .down,
                    x: 100 + i * 10,
                    y: 100 + i * 10,
                    button: 0
                )
                events.append(event)
            } else {
                // Move event
                let event = TelemetryRecorder.Event(
                    t: timestamp,
                    type: .move,
                    x: 100 + i * 10,
                    y: 100 + i * 10
                )
                events.append(event)
            }
        }

        return events
    }
}
