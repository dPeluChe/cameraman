//
//  ZoomPlanGenerator.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// ZoomPlanGenerator generates zoom keyframe plans from telemetry parser results
/// Provides smooth camera movements with easing functions and configurable limits (Épica I, Task 2)
public actor ZoomPlanGenerator {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Generate a zoom plan from telemetry parser results
    /// - Parameters:
    ///   - parseResult: Result from TelemetryParser containing click windows
    ///   - config: Zoom plan generation configuration
    ///   - timelineDuration: Total timeline duration for stats calculation
    ///   - screenWidth/screenHeight: dimensions of the coordinate space the
    ///     click windows live in (capture points) — required for correct focus
    ///     normalization on anything that isn't a 1920×1080 screen
    /// - Returns: ZoomPlan with zoom events and keyframes
    public func generateZoomPlan(
        from parseResult: TelemetryParser.ParseResult,
        config: Configuration = .default(),
        timelineDuration: TimeInterval? = nil,
        screenWidth: Double = 1920,
        screenHeight: Double = 1080
    ) async throws -> ZoomPlan {
        // Validate configuration
        try config.validate()

        // Check if zoom is enabled
        guard config.zoomEnabled else {
            return createEmptyZoomPlan(config: config)
        }

        // Get click windows from parse result
        let clickWindows = parseResult.windows

        guard !clickWindows.isEmpty else {
            throw ZoomPlanError.noClickWindows
        }

        // Sort windows by start time and filter by importance
        let sortedWindows = clickWindows.sorted { $0.startTime < $1.startTime }
        var filteredWindows = filterWindowsByImportance(sortedWindows)

        // Respect the per-minute rate limit by dropping the lowest-importance
        // windows instead of throwing — keep consistent with the array-based
        // generateZoomPlan overload. A previous throw here, silenced by a
        // `try?` upstream, was the root cause of "suggestions visible but no
        // zoom applied" (see CHANGELOG 0.5.1 Fixed).
        let duration = timelineDuration ?? (parseResult.stats.timeRange.upperBound - parseResult.stats.timeRange.lowerBound)
        filteredWindows = capWindowsToRateLimit(filteredWindows, duration: duration, config: config)

        // Generate zoom events from click windows
        var zoomEvents: [ZoomEvent] = []
        var lastZoomEndTime: TimeInterval = 0

        for window in filteredWindows {
            // Check minimum time between zooms
            if lastZoomEndTime > 0 && (window.startTime - lastZoomEndTime) < config.minTimeBetweenZooms {
                continue // Skip this zoom event (too soon after previous)
            }

            // Calculate zoom level based on bounding box size
            let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
            let referenceArea = max(1.0, screenWidth * screenHeight)
            let normalizedArea = boundingBoxArea / referenceArea
            let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: config)

            // Calculate focus point (center of click window) using the caller-provided
            // screen dims — a hardcoded 1920×1080 maps wrong on any other screen
            let focusX = window.centerPoint.x / CGFloat(screenWidth)
            let focusY = window.centerPoint.y / CGFloat(screenHeight)

            // Calculate timing
            let zoomInStart = window.startTime
            let zoomInEnd = zoomInStart + config.zoomInDuration
            let holdEnd = zoomInEnd + config.holdDuration
            let zoomOutEnd = holdEnd + config.zoomOutDuration

            // Create zoom event
            let zoomEvent = ZoomEvent(
                zoomInStartTime: zoomInStart,
                zoomInEndTime: zoomInEnd,
                holdEndTime: holdEnd,
                zoomOutEndTime: zoomOutEnd,
                targetZoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                clickWindowId: window.id,
                easing: config.easingFunction
            )

            zoomEvents.append(zoomEvent)
            lastZoomEndTime = zoomOutEnd
        }

        // Generate keyframes from zoom events
        let keyframes = generateKeyframes(from: zoomEvents, config: config)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: zoomEvents,
            keyframes: keyframes,
            config: config,
            duration: duration
        )

        return ZoomPlan(
            events: zoomEvents,
            keyframes: keyframes,
            configuration: config,
            stats: stats
        )
    }

    /// Generate a zoom plan from click windows directly (without parse result)
    /// - Parameters:
    ///   - clickWindows: Array of click windows from telemetry parser
    ///   - config: Zoom plan generation configuration
    ///   - timelineDuration: Total timeline duration for stats calculation
    /// - Returns: ZoomPlan with zoom events and keyframes
    public func generateZoomPlan(
        from clickWindows: [TelemetryParser.ClickWindow],
        config: Configuration = .default(),
        timelineDuration: TimeInterval,
        screenWidth: Double = 1920,
        screenHeight: Double = 1080
    ) async throws -> ZoomPlan {
        // Validate configuration
        try config.validate()

        // Check if zoom is enabled
        guard config.zoomEnabled else {
            return createEmptyZoomPlan(config: config)
        }

        guard !clickWindows.isEmpty else {
            throw ZoomPlanError.noClickWindows
        }

        // Sort windows by start time and filter by importance
        let sortedWindows = clickWindows.sorted { $0.startTime < $1.startTime }
        var filteredWindows = filterWindowsByImportance(sortedWindows)

        // Respect the per-minute rate limit by dropping the lowest-importance windows
        // instead of throwing. Previously this validation tripped and the caller's
        // `try?` silenced the error — leaving timeline markers with no actual zoom applied.
        filteredWindows = capWindowsToRateLimit(filteredWindows, duration: timelineDuration, config: config)

        // Generate zoom events from click windows
        var zoomEvents: [ZoomEvent] = []
        var lastZoomEndTime: TimeInterval = 0

        for window in filteredWindows {
            // Check minimum time between zooms
            if lastZoomEndTime > 0 && (window.startTime - lastZoomEndTime) < config.minTimeBetweenZooms {
                continue // Skip this zoom event (too soon after previous)
            }

            // Calculate zoom level based on bounding box size
            let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
            let referenceArea = max(1.0, screenWidth * screenHeight)
            let normalizedArea = boundingBoxArea / referenceArea
            let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: config)

            // Calculate focus point (center of click window) using the caller-provided screen dims
            // rather than a hardcoded 1920x1080 — otherwise ultrawides and area recordings map wrong.
            let focusX = window.centerPoint.x / CGFloat(screenWidth)
            let focusY = window.centerPoint.y / CGFloat(screenHeight)

            // Calculate timing
            let zoomInStart = window.startTime
            let zoomInEnd = zoomInStart + config.zoomInDuration
            let holdEnd = zoomInEnd + config.holdDuration
            let zoomOutEnd = holdEnd + config.zoomOutDuration

            // Create zoom event
            let zoomEvent = ZoomEvent(
                zoomInStartTime: zoomInStart,
                zoomInEndTime: zoomInEnd,
                holdEndTime: holdEnd,
                zoomOutEndTime: zoomOutEnd,
                targetZoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                clickWindowId: window.id,
                easing: config.easingFunction
            )

            zoomEvents.append(zoomEvent)
            lastZoomEndTime = zoomOutEnd
        }

        // Generate keyframes from zoom events
        let keyframes = generateKeyframes(from: zoomEvents, config: config)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: zoomEvents,
            keyframes: keyframes,
            config: config,
            duration: timelineDuration
        )

        return ZoomPlan(
            events: zoomEvents,
            keyframes: keyframes,
            configuration: config,
            stats: stats
        )
    }

    // MARK: - Private Methods

    /// Create an empty zoom plan (when zoom is disabled)
    private func createEmptyZoomPlan(config: Configuration) -> ZoomPlan {
        let emptyStats = ZoomPlanStats(
            totalZoomEvents: 0,
            totalKeyframes: 0,
            totalZoomedTime: 0,
            zoomedTimePercentage: 0,
            averageZoomLevel: config.defaultZoomLevel,
            maximumZoomLevel: config.defaultZoomLevel,
            averageTimeBetweenZooms: 0,
            zoomsPerMinute: 0,
            timeRange: 0...0
        )

        return ZoomPlan(
            events: [],
            keyframes: [],
            configuration: config,
            stats: emptyStats
        )
    }

    /// Filter windows by importance (remove low-importance windows)
    func filterWindowsByImportance(_ windows: [TelemetryParser.ClickWindow]) -> [TelemetryParser.ClickWindow] {
        guard windows.count > 1 else { return windows }

        // Calculate median importance score
        let sortedScores = windows.map { $0.importanceScore }.sorted()
        let medianIndex = sortedScores.count / 2
        let medianScore = sortedScores[medianIndex]

        // Filter to keep only windows above median importance
        return windows.filter { $0.importanceScore >= medianScore }
    }

    /// Validate zoom rate limits
    func validateZoomRate(
        for windows: [TelemetryParser.ClickWindow],
        duration: TimeInterval,
        config: Configuration
    ) throws {
        guard duration > 0 else { return }

        let zoomsPerMinute = Double(windows.count) / (duration / 60.0)

        if zoomsPerMinute > Double(config.maxZoomsPerMinute) {
            throw ZoomPlanError.zoomRateExceeded(
                Int(zoomsPerMinute),
                config.maxZoomsPerMinute
            )
        }
    }

    /// Keep at most `maxZoomsPerMinute * minutes` windows, preferring the highest-importance
    /// ones. Result is re-sorted by time so downstream `minTimeBetweenZooms` filtering still works.
    func capWindowsToRateLimit(
        _ windows: [TelemetryParser.ClickWindow],
        duration: TimeInterval,
        config: Configuration
    ) -> [TelemetryParser.ClickWindow] {
        guard duration > 0 else { return windows }

        let minutes = duration / 60.0
        let maxAllowed = max(1, Int(ceil(Double(config.maxZoomsPerMinute) * minutes)))
        if windows.count <= maxAllowed { return windows }

        let kept = windows
            .sorted { $0.importanceScore > $1.importanceScore }
            .prefix(maxAllowed)
        return kept.sorted { $0.startTime < $1.startTime }
    }

    /// Calculate zoom level based on bounding box area
    func calculateZoomLevel(for normalizedArea: Double, config: Configuration) -> Double {
        // Smaller area = higher zoom level
        // Larger area = lower zoom level

        // Map area to zoom level (inverse relationship)
        // Area range: ~0.01 (small click cluster) to ~1.0 (full screen)
        // Zoom range: config.minZoomLevel to config.maxZoomLevel

        let clampedArea = max(0.01, min(1.0, normalizedArea))

        // Inverse mapping: smaller area -> higher zoom
        let zoomRange = config.maxZoomLevel - config.minZoomLevel
        let zoomLevel = config.maxZoomLevel - (clampedArea * zoomRange)

        return max(config.minZoomLevel, min(config.maxZoomLevel, zoomLevel))
    }

    /// Generate keyframes from zoom events
    func generateKeyframes(from zoomEvents: [ZoomEvent], config: Configuration) -> [ZoomKeyframe] {
        var allKeyframes: [ZoomKeyframe] = []

        for event in zoomEvents {
            let eventKeyframes = event.generateKeyframes(defaultZoomLevel: config.defaultZoomLevel)
            allKeyframes.append(contentsOf: eventKeyframes)
        }

        // Sort by timestamp
        return allKeyframes.sorted { $0.timestamp < $1.timestamp }
    }

    /// Calculate zoom plan statistics
    func calculateZoomPlanStats(
        events: [ZoomEvent],
        keyframes: [ZoomKeyframe],
        config: Configuration,
        duration: TimeInterval
    ) -> ZoomPlanStats {
        guard !events.isEmpty else {
            return ZoomPlanStats(
                totalZoomEvents: 0,
                totalKeyframes: 0,
                totalZoomedTime: 0,
                zoomedTimePercentage: 0,
                averageZoomLevel: config.defaultZoomLevel,
                maximumZoomLevel: config.defaultZoomLevel,
                averageTimeBetweenZooms: 0,
                zoomsPerMinute: 0,
                timeRange: 0...duration
            )
        }

        // Calculate total zoomed time
        let totalZoomedTime = events.reduce(0) { $0 + $1.totalDuration }
        let zoomedTimePercentage = duration > 0 ? (totalZoomedTime / duration) * 100 : 0

        // Calculate average and max zoom levels
        let zoomLevels = events.map { $0.targetZoomLevel }
        let averageZoomLevel = zoomLevels.reduce(0, +) / Double(zoomLevels.count)
        let maximumZoomLevel = zoomLevels.max() ?? config.defaultZoomLevel

        // Calculate average time between zooms
        let averageTimeBetweenZooms: TimeInterval
        if events.count > 1 {
            let intervals = zip(events, events.dropFirst()).map { $1.zoomInStartTime - $0.zoomOutEndTime }
            averageTimeBetweenZooms = intervals.reduce(0, +) / Double(intervals.count)
        } else {
            averageTimeBetweenZooms = 0
        }

        // Calculate zooms per minute
        let zoomsPerMinute = duration > 0 ? Double(events.count) / (duration / 60.0) : 0

        // Time range
        let timeRange = 0...duration

        return ZoomPlanStats(
            totalZoomEvents: events.count,
            totalKeyframes: keyframes.count,
            totalZoomedTime: totalZoomedTime,
            zoomedTimePercentage: zoomedTimePercentage,
            averageZoomLevel: averageZoomLevel,
            maximumZoomLevel: maximumZoomLevel,
            averageTimeBetweenZooms: averageTimeBetweenZooms,
            zoomsPerMinute: zoomsPerMinute,
            timeRange: timeRange
        )
    }

    // MARK: - Manual-Only Plan

    /// Build a ZoomPlan containing only manual keyframes (no auto events).
    /// Used when telemetry is absent but the user has placed manual keyframes.
    public nonisolated static func manualOnlyPlan(
        from keyframes: [ZoomKeyframe]
    ) -> ZoomPlan {
        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }
        return ZoomPlan(
            events: [],
            keyframes: sorted,
            configuration: .default(),
            stats: ZoomPlanStats(
                totalZoomEvents: 0,
                totalKeyframes: sorted.count,
                totalZoomedTime: 0,
                zoomedTimePercentage: 0,
                averageZoomLevel: 1,
                maximumZoomLevel: sorted.map(\.zoomLevel).max() ?? 1,
                averageTimeBetweenZooms: 0,
                zoomsPerMinute: 0,
                timeRange: 0...0
            )
        )
    }

}
