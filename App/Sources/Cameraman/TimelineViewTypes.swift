//
//  TimelineViewTypes.swift
//  App
//
//  Extracted from TimelineView.swift
//  Core types for timeline: track kinds, tracks, builder, layout
//

import SwiftUI
import EngineKit
import CoreGraphics

typealias TimelineScalar = CoreGraphics.CGFloat

enum TimelineTrackKind: String, CaseIterable, Identifiable {
    case screen
    case camera
    case systemAudio
    case micAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen:
            return "Screen"
        case .camera:
            return "Camera"
        case .systemAudio:
            return "System Audio"
        case .micAudio:
            return "Mic Audio"
        }
    }

    var color: Color {
        switch self {
        case .screen:
            return Color.blue.opacity(0.85)
        case .camera:
            return Color.green.opacity(0.85)
        case .systemAudio:
            return Color.orange.opacity(0.85)
        case .micAudio:
            return Color.pink.opacity(0.85)
        }
    }
}

struct TimelineTrack: Identifiable {
    let kind: TimelineTrackKind
    let segments: [Project.Timeline.Segment]

    var id: TimelineTrackKind { kind }
    var label: String { kind.label }
    var color: Color { kind.color }
}

enum TimelineTrackBuilder {
    static func tracks(for project: Project) -> [TimelineTrack] {
        var tracks: [TimelineTrack] = [
            TimelineTrack(kind: .screen, segments: project.timeline.segments)
        ]

        if project.primarySources?.camera != nil {
            tracks.append(TimelineTrack(kind: .camera, segments: project.timeline.segments))
        }

        if project.primarySources?.audio?.system != nil {
            tracks.append(TimelineTrack(kind: .systemAudio, segments: project.timeline.segments))
        }

        if project.primarySources?.audio?.mic != nil {
            tracks.append(TimelineTrack(kind: .micAudio, segments: project.timeline.segments))
        }

        return tracks
    }
}

struct TimelineLayout {
    let duration: TimeInterval
    let pixelsPerSecond: TimelineScalar
    let labelWidth: TimelineScalar
    let minimumSegmentWidth: TimelineScalar = 6

    var contentWidth: TimelineScalar {
        let timelineWidth = max(1, TimelineScalar(duration) * pixelsPerSecond)
        return labelWidth + timelineWidth
    }

    func xPosition(for time: TimeInterval) -> TimelineScalar {
        let safeTime = max(0, time)
        return labelWidth + TimelineScalar(safeTime) * pixelsPerSecond
    }

    func segmentWidth(for duration: TimeInterval) -> TimelineScalar {
        let safeDuration = max(0, duration)
        return max(minimumSegmentWidth, TimelineScalar(safeDuration) * pixelsPerSecond)
    }

    func time(forXPosition xPosition: TimelineScalar) -> TimeInterval {
        let effectivePixelsPerSecond = max(pixelsPerSecond, 0.001)
        let timelineX = max(0, xPosition - labelWidth)
        let time = TimeInterval(timelineX / effectivePixelsPerSecond)
        return min(max(0, time), duration)
    }
}
