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

enum TimelineTrackKind: String, CaseIterable, Identifiable, Hashable {
    case screen
    case camera
    case systemAudio
    case micAudio
    case additionalAudio
    case imageOverlay
    case overlay

    var id: String { rawValue }

    var isAudioTrack: Bool {
        self == .systemAudio || self == .micAudio
    }

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
        case .additionalAudio:
            return "Music / Audio"
        case .imageOverlay:
            return "Images"
        case .overlay:
            return "Overlays"
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
        case .additionalAudio:
            return Color.purple.opacity(0.85)
        case .imageOverlay:
            return Color.yellow.opacity(0.85)
        case .overlay:
            return Color.cyan.opacity(0.85)
        }
    }
}

/// A timeline track that can hold either recording segments or imported media items
struct TimelineTrack: Identifiable {
    let kind: TimelineTrackKind
    let segments: [Project.Timeline.Segment]
    let mediaItems: [Project.MediaItem]
    let overlays: [Project.Overlay]

    var id: TimelineTrackKind { kind }
    var label: String { kind.label }
    var color: Color { kind.color }

    init(kind: TimelineTrackKind, segments: [Project.Timeline.Segment], mediaItems: [Project.MediaItem] = [], overlays: [Project.Overlay] = []) {
        self.kind = kind
        self.segments = segments
        self.mediaItems = mediaItems
        self.overlays = overlays
    }
}

enum TimelineTrackBuilder {
    /// Build the ordered list of timeline tracks. Convention: overlays at the
    /// TOP so users can see/manipulate them above the primary video tracks
    /// (same pattern as Final Cut / Premiere where overlay/effect tracks
    /// sit above the base video). Order top→bottom:
    ///   1. overlay (shapes + images, single row with visual stacking)
    ///   2. imageOverlay legacy (mediaItems with type=.image) — kept for back-compat
    ///   3. screen
    ///   4. camera (if available)
    ///   5. systemAudio (if available)
    ///   6. micAudio (if available)
    ///   7. additionalAudio (imported music / voiceover)
    static func tracks(for project: Project) -> [TimelineTrack] {
        var tracks: [TimelineTrack] = []

        // Shape + image overlay track (arrows, rects, lines, text, image)
        if !project.overlays.isEmpty {
            tracks.append(TimelineTrack(kind: .overlay, segments: [], overlays: project.overlays))
        }

        // Legacy image overlay tracks (mediaItems-based, predates the unified
        // Project.Overlay.image type — kept for back-compat with existing
        // projects that used the old import-as-mediaItem flow).
        let imageItems = project.mediaItems.filter { $0.type == .image }
        if !imageItems.isEmpty {
            tracks.append(TimelineTrack(kind: .imageOverlay, segments: [], mediaItems: imageItems))
        }

        tracks.append(TimelineTrack(kind: .screen, segments: project.timeline.segments))

        if project.primarySources?.camera != nil {
            tracks.append(TimelineTrack(kind: .camera, segments: project.timeline.segments))
        }

        if project.primarySources?.audio?.system != nil {
            tracks.append(TimelineTrack(kind: .systemAudio, segments: project.timeline.segments))
        }

        if project.primarySources?.audio?.mic != nil {
            tracks.append(TimelineTrack(kind: .micAudio, segments: project.timeline.segments))
        }

        // Additional audio tracks (imported music, voiceover) at the bottom
        let audioItems = project.mediaItems.filter { $0.type == .audio }
        if !audioItems.isEmpty {
            tracks.append(TimelineTrack(kind: .additionalAudio, segments: [], mediaItems: audioItems))
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
