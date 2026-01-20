//
//  TimelineEditingHelper.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//

import Foundation
import EngineKit

enum TimelineEditingHelper {
    static func segmentForSplit(at time: TimeInterval, in segments: [Project.Timeline.Segment]) -> Project.Timeline.Segment? {
        segments.first(where: { time > $0.timelineIn && time < $0.timelineOut })
    }

    static func sourceIn(for segment: Project.Timeline.Segment, newTimelineIn: TimeInterval) -> TimeInterval {
        segment.sourceIn + (newTimelineIn - segment.timelineIn) * segment.speed
    }

    static func sourceOut(for segment: Project.Timeline.Segment, newTimelineOut: TimeInterval) -> TimeInterval {
        segment.sourceIn + (newTimelineOut - segment.timelineIn) * segment.speed
    }

    static func clampedTimelineIn(
        for segment: Project.Timeline.Segment,
        proposedTime: TimeInterval,
        minimumDuration: TimeInterval
    ) -> TimeInterval {
        min(max(proposedTime, segment.timelineIn), segment.timelineOut - minimumDuration)
    }

    static func clampedTimelineOut(
        for segment: Project.Timeline.Segment,
        proposedTime: TimeInterval,
        minimumDuration: TimeInterval
    ) -> TimeInterval {
        max(min(proposedTime, segment.timelineOut), segment.timelineIn + minimumDuration)
    }
}
