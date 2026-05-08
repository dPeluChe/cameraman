//
//  ZoomPlan+Filter.swift
//  EngineKit
//
//  Filtering helpers that honor per-segment ZoomConfiguration.enabled state.
//

import Foundation

extension ZoomPlanGenerator.ZoomPlan {
    /// Drop events whose start falls inside a segment with `zoom.enabled == false`,
    /// then regenerate keyframes from the survivors. Segments with `zoom == nil`
    /// are treated as enabled (matches the rest of the codebase: a missing config
    /// means "use defaults").
    public func filtered(
        byEnabledSegments segments: [Project.Timeline.Segment]
    ) -> ZoomPlanGenerator.ZoomPlan {
        guard !segments.isEmpty else { return self }

        let enabledRanges: [ClosedRange<TimeInterval>] = segments.compactMap { seg in
            let enabled = seg.zoom?.enabled ?? true
            guard enabled else { return nil }
            return seg.timelineIn...seg.timelineOut
        }

        let filteredEvents = events.filter { event in
            enabledRanges.contains { $0.contains(event.zoomInStartTime) }
        }

        let newKeyframes = filteredEvents
            .flatMap { $0.generateKeyframes(defaultZoomLevel: configuration.defaultZoomLevel) }
            .sorted { $0.timestamp < $1.timestamp }

        return ZoomPlanGenerator.ZoomPlan(
            events: filteredEvents,
            keyframes: newKeyframes,
            configuration: configuration,
            stats: stats
        )
    }

    public var hasNoZoom: Bool { events.isEmpty || keyframes.isEmpty }
}
