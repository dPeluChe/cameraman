//
//  ZoomPlanGeneratorSections.swift
//  EngineKit
//
//  Extracted from ZoomPlanGenerator.swift — per-segment zoom plan generation
//

import Foundation

extension ZoomPlanGenerator {
    /// Generate a zoom plan with per-segment configuration (Épica I, Task 4)
    public func generateZoomPlanWithSections(
        from parseResult: TelemetryParser.ParseResult,
        segments: [Project.Timeline.Segment],
        defaultConfig: Configuration = .default(),
        timelineDuration: TimeInterval? = nil
    ) async throws -> ZoomPlan {
        let duration = timelineDuration ?? (parseResult.stats.timeRange.upperBound - parseResult.stats.timeRange.lowerBound)

        let (allZoomEvents, allKeyframes) = try generateSectionZoomEvents(
            clickWindows: parseResult.windows,
            segments: segments,
            defaultConfig: defaultConfig
        )

        let stats = calculateZoomPlanStats(
            events: allZoomEvents,
            keyframes: allKeyframes,
            config: defaultConfig,
            duration: duration
        )

        return ZoomPlan(
            events: allZoomEvents,
            keyframes: allKeyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }

    /// Generate a zoom plan with per-segment configuration from click windows directly
    public func generateZoomPlanWithSections(
        from clickWindows: [TelemetryParser.ClickWindow],
        segments: [Project.Timeline.Segment],
        defaultConfig: Configuration = .default(),
        timelineDuration: TimeInterval
    ) async throws -> ZoomPlan {
        let (allZoomEvents, allKeyframes) = try generateSectionZoomEvents(
            clickWindows: clickWindows,
            segments: segments,
            defaultConfig: defaultConfig
        )

        let stats = calculateZoomPlanStats(
            events: allZoomEvents,
            keyframes: allKeyframes,
            config: defaultConfig,
            duration: timelineDuration
        )

        return ZoomPlan(
            events: allZoomEvents,
            keyframes: allKeyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }

    /// Shared logic for generating zoom events from segments
    private func generateSectionZoomEvents(
        clickWindows: [TelemetryParser.ClickWindow],
        segments: [Project.Timeline.Segment],
        defaultConfig: Configuration
    ) throws -> ([ZoomEvent], [ZoomKeyframe]) {
        var allZoomEvents: [ZoomEvent] = []

        for segment in segments {
            let segmentConfig = resolveSegmentConfig(segment: segment, defaultConfig: defaultConfig)

            guard segmentConfig.zoomEnabled else { continue }

            let segmentClickWindows = clickWindows.filter { window in
                window.startTime >= segment.timelineIn && window.startTime <= segment.timelineOut
            }

            guard !segmentClickWindows.isEmpty else { continue }

            let sortedWindows = segmentClickWindows.sorted { $0.startTime < $1.startTime }
            var filteredWindows = filterWindowsByImportance(sortedWindows)

            // Respect the per-minute rate limit by dropping low-importance
            // windows instead of throwing — same trim-not-abort policy as
            // the top-level generateZoomPlan overloads.
            let segmentDuration = segment.timelineOut - segment.timelineIn
            filteredWindows = capWindowsToRateLimit(filteredWindows, duration: segmentDuration, config: segmentConfig)

            var lastZoomEndTime: TimeInterval = segment.timelineIn

            for window in filteredWindows {
                if lastZoomEndTime > segment.timelineIn && (window.startTime - lastZoomEndTime) < segmentConfig.minTimeBetweenZooms {
                    continue
                }

                let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
                let normalizedArea = boundingBoxArea / 2_500_000.0
                let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: segmentConfig)

                let focusX = window.centerPoint.x / 1920.0
                let focusY = window.centerPoint.y / 1080.0

                let zoomInStart = window.startTime
                let zoomInEnd = zoomInStart + segmentConfig.zoomInDuration
                let holdEnd = zoomInEnd + segmentConfig.holdDuration
                let zoomOutEnd = holdEnd + segmentConfig.zoomOutDuration

                let zoomEvent = ZoomEvent(
                    zoomInStartTime: zoomInStart,
                    zoomInEndTime: zoomInEnd,
                    holdEndTime: holdEnd,
                    zoomOutEndTime: zoomOutEnd,
                    targetZoomLevel: targetZoomLevel,
                    focusX: focusX,
                    focusY: focusY,
                    clickWindowId: window.id,
                    easing: segmentConfig.easingFunction
                )

                allZoomEvents.append(zoomEvent)
                lastZoomEndTime = zoomOutEnd
            }
        }

        let allKeyframes = generateKeyframes(from: allZoomEvents, config: defaultConfig)
        return (allZoomEvents, allKeyframes)
    }

    /// Resolve the effective zoom configuration for a segment
    private func resolveSegmentConfig(
        segment: Project.Timeline.Segment,
        defaultConfig: Configuration
    ) -> Configuration {
        guard let zoomConfig = segment.zoom else {
            return defaultConfig
        }

        if let intensity = zoomConfig.intensity {
            return intensity.toConfiguration(base: defaultConfig)
        }

        return Configuration(
            minZoomLevel: zoomConfig.minZoomLevel,
            maxZoomLevel: zoomConfig.maxZoomLevel,
            defaultZoomLevel: defaultConfig.defaultZoomLevel,
            zoomInDuration: defaultConfig.zoomInDuration,
            zoomOutDuration: defaultConfig.zoomOutDuration,
            holdDuration: defaultConfig.holdDuration,
            boundingBoxPadding: defaultConfig.boundingBoxPadding,
            easingFunction: defaultConfig.easingFunction,
            maxZoomsPerMinute: defaultConfig.maxZoomsPerMinute,
            minTimeBetweenZooms: defaultConfig.minTimeBetweenZooms,
            zoomEnabled: zoomConfig.enabled
        )
    }
}
