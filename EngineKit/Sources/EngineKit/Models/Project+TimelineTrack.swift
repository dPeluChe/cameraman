//
//  Project+TimelineTrack.swift
//  EngineKit
//
//  Multi-track timeline model. Each track contains clips of a specific type.
//  This replaces the flat segments[] model with a layered track/clip architecture
//  that supports recording segments, images, imported video, audio, and colors.
//

import Foundation

// MARK: - Track Type

extension Project {

    /// The type of content a track holds
    public enum TrackType: String, Codable, Sendable, CaseIterable {
        /// Primary recording track (screen + camera + audio from Takes)
        case primary
        /// Imported video or images (B-roll, slides, title cards)
        case video
        /// Imported audio (music, sound effects, voiceover)
        case audio
    }
}

// MARK: - Timeline Track

extension Project {

    /// A track in the timeline containing clips of a specific type
    public struct TimelineTrack: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        /// Display name for the track
        public var name: String
        /// What kind of content this track holds
        public var type: TrackType
        /// Ordered list of clips in this track
        public var clips: [TimelineClip]
        /// Whether the entire track is muted (audio) or hidden (video)
        public var isMuted: Bool
        /// Whether the track is locked from editing
        public var isLocked: Bool
        /// Track volume multiplier (for audio tracks, 0.0-1.0)
        public var volume: Double
        /// Track opacity (for video tracks, 0.0-1.0)
        public var opacity: Double

        public init(
            id: UUID = UUID(),
            name: String = "",
            type: TrackType,
            clips: [TimelineClip] = [],
            isMuted: Bool = false,
            isLocked: Bool = false,
            volume: Double = 1.0,
            opacity: Double = 1.0
        ) {
            self.id = id
            self.name = name.isEmpty ? type.defaultName : name
            self.type = type
            self.clips = clips
            self.isMuted = isMuted
            self.isLocked = isLocked
            self.volume = volume
            self.opacity = opacity
        }
    }
}

// MARK: - Timeline Clip

extension Project {

    /// A clip placed on a track at a specific timeline position
    public struct TimelineClip: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        /// Start position on the timeline (seconds)
        public var timelineIn: TimeInterval
        /// What this clip contains
        public var content: ClipContent
        /// Playback speed multiplier (for recording/video/audio clips)
        public var speed: Double
        /// Per-clip volume override (nil = use track default)
        public var volume: Double?
        /// Per-clip opacity override (nil = use track default)
        public var opacity: Double?
        /// Position on canvas for image/video clips (nil = fullscreen)
        public var position: MediaPosition?

        /// Duration on the timeline (derived from content and speed)
        public var duration: TimeInterval {
            switch content {
            case .recording(let ref):
                return (ref.sourceOut - ref.sourceIn) / speed
            case .video(let ref):
                return (ref.sourceOut - ref.sourceIn) / speed
            case .image(let ref):
                return ref.duration
            case .audio(let ref):
                return ref.duration / speed
            case .color(let ref):
                return ref.duration
            }
        }

        /// End position on the timeline
        public var timelineOut: TimeInterval {
            timelineIn + duration
        }

        public init(
            id: String = UUID().uuidString,
            timelineIn: TimeInterval,
            content: ClipContent,
            speed: Double = 1.0,
            volume: Double? = nil,
            opacity: Double? = nil,
            position: MediaPosition? = nil
        ) {
            self.id = id
            self.timelineIn = timelineIn
            self.content = content
            self.speed = speed
            self.volume = volume
            self.opacity = opacity
            self.position = position
        }
    }
}

// MARK: - Clip Content

extension Project {

    /// The content of a timeline clip
    public enum ClipContent: Codable, Equatable, Sendable {
        /// A segment from a recorded Take (screen + camera + audio)
        case recording(RecordingClipRef)
        /// A static image displayed for a set duration
        case image(ImageClipRef)
        /// An imported video file
        case video(VideoClipRef)
        /// An audio file (music, voiceover, sound effect)
        case audio(AudioClipRef)
        /// A solid color card (title card, transition, blank)
        case color(ColorClipRef)
    }

    /// Reference to a recorded take's source media
    public struct RecordingClipRef: Codable, Equatable, Sendable {
        /// ID of the Take this clip references (nil = legacy/first take)
        public var takeId: UUID?
        /// Start time in source media (seconds)
        public var sourceIn: TimeInterval
        /// End time in source media (seconds)
        public var sourceOut: TimeInterval
        /// Per-clip zoom configuration override
        public var zoom: Timeline.ZoomConfiguration?
        /// Per-clip camera position override
        public var cameraPosition: Canvas.Layout.CameraPosition?
        /// Per-clip audio mute
        public var audioMuted: Bool?

        public init(
            takeId: UUID? = nil,
            sourceIn: TimeInterval,
            sourceOut: TimeInterval,
            zoom: Timeline.ZoomConfiguration? = nil,
            cameraPosition: Canvas.Layout.CameraPosition? = nil,
            audioMuted: Bool? = nil
        ) {
            self.takeId = takeId
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
            self.zoom = zoom
            self.cameraPosition = cameraPosition
            self.audioMuted = audioMuted
        }
    }

    /// Reference to a static image file
    public struct ImageClipRef: Codable, Equatable, Sendable {
        /// Relative path to image within project assets
        public var path: String
        /// How long to display the image (seconds)
        public var duration: TimeInterval

        public init(path: String, duration: TimeInterval = 5.0) {
            self.path = path
            self.duration = duration
        }
    }

    /// Reference to an imported video file
    public struct VideoClipRef: Codable, Equatable, Sendable {
        /// Relative path to video within project assets
        public var path: String
        /// Start time in source video (seconds)
        public var sourceIn: TimeInterval
        /// End time in source video (seconds)
        public var sourceOut: TimeInterval

        public init(path: String, sourceIn: TimeInterval = 0, sourceOut: TimeInterval) {
            self.path = path
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
        }
    }

    /// Reference to an audio file
    public struct AudioClipRef: Codable, Equatable, Sendable {
        /// Relative path to audio within project assets
        public var path: String
        /// Duration to play (seconds)
        public var duration: TimeInterval
        /// Start offset in source audio (seconds)
        public var sourceIn: TimeInterval

        public init(path: String, duration: TimeInterval, sourceIn: TimeInterval = 0) {
            self.path = path
            self.duration = duration
            self.sourceIn = sourceIn
        }
    }

    /// Reference to a solid color fill
    public struct ColorClipRef: Codable, Equatable, Sendable {
        /// Hex color string (e.g. "#000000", "#FF5500AA")
        public var hexColor: String
        /// How long to display (seconds)
        public var duration: TimeInterval

        public init(hexColor: String = "#000000", duration: TimeInterval = 3.0) {
            self.hexColor = hexColor
            self.duration = duration
        }
    }
}

// MARK: - Track Type Helpers

extension Project.TrackType {
    /// Default display name for this track type
    public var defaultName: String {
        switch self {
        case .primary: return "Recording"
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
}

// MARK: - Well-Known Track IDs

extension Project.TimelineTrack {
    /// Deterministic ID for the primary recording track.
    /// Ensures Equatable consistency when constructing from segments.
    public static let primaryTrackId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

// MARK: - TimelineTrack Helpers

extension Project.TimelineTrack {
    /// The end time of the last clip in this track
    public var endTime: TimeInterval {
        clips.map(\.timelineOut).max() ?? 0
    }

    /// Whether this track has any clips
    public var isEmpty: Bool {
        clips.isEmpty
    }

    /// Get clips that overlap a given time range
    public func clips(in range: ClosedRange<TimeInterval>) -> [Project.TimelineClip] {
        clips.filter { clip in
            clip.timelineIn < range.upperBound && clip.timelineOut > range.lowerBound
        }
    }

    /// Get the clip at a specific time, if any
    public func clip(at time: TimeInterval) -> Project.TimelineClip? {
        clips.first { clip in
            time >= clip.timelineIn && time < clip.timelineOut
        }
    }
}

// MARK: - TimelineClip Conversion Helpers

extension Project.TimelineClip {
    /// Create a clip from a legacy Segment
    public static func fromSegment(_ segment: Project.Timeline.Segment) -> Project.TimelineClip {
        Project.TimelineClip(
            id: segment.id,
            timelineIn: segment.timelineIn,
            content: .recording(Project.RecordingClipRef(
                takeId: segment.takeId,
                sourceIn: segment.sourceIn,
                sourceOut: segment.sourceOut,
                zoom: segment.zoom,
                cameraPosition: segment.cameraPosition,
                audioMuted: segment.audioMuted
            )),
            speed: segment.speed,
            volume: segment.volume
        )
    }

    /// Create a clip from a legacy MediaItem
    public static func fromMediaItem(_ item: Project.MediaItem) -> Project.TimelineClip {
        switch item.type {
        case .image:
            return Project.TimelineClip(
                id: item.id.uuidString,
                timelineIn: item.timelineIn,
                content: .image(Project.ImageClipRef(
                    path: item.path,
                    duration: item.duration
                )),
                opacity: item.opacity,
                position: item.position
            )
        case .audio:
            return Project.TimelineClip(
                id: item.id.uuidString,
                timelineIn: item.timelineIn,
                content: .audio(Project.AudioClipRef(
                    path: item.path,
                    duration: item.duration
                )),
                volume: item.volume
            )
        }
    }

    /// Whether this clip contains a recording
    public var isRecording: Bool {
        if case .recording = content { return true }
        return false
    }

    /// Whether this clip contains visual content (recording, image, video, color)
    public var isVisual: Bool {
        switch content {
        case .recording, .image, .video, .color: return true
        case .audio: return false
        }
    }

    /// Whether this clip contains audio content
    public var isAudio: Bool {
        switch content {
        case .audio: return true
        case .recording: return true // recordings have audio
        default: return false
        }
    }

    /// Get the recording reference if this is a recording clip
    public var recordingRef: Project.RecordingClipRef? {
        if case .recording(let ref) = content { return ref }
        return nil
    }
}
