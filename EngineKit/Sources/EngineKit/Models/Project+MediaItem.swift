//
//  Project+MediaItem.swift
//  EngineKit
//
//  Imported media assets (audio, images) placed on the timeline.
//

import Foundation

extension Project {

    /// An imported media asset placed on the timeline
    public struct MediaItem: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        /// Type of media
        public var type: MediaItemType
        /// Relative path to the asset file within project/assets/ directory
        public var path: String
        /// Display name
        public var name: String
        /// Start position on timeline (seconds)
        public var timelineIn: TimeInterval
        /// Duration on timeline (seconds)
        public var duration: TimeInterval
        /// Volume (for audio items, 0.0-1.0)
        public var volume: Double
        /// Opacity (for image/video items, 0.0-1.0)
        public var opacity: Double
        /// Position on canvas (for image items, normalized 0-1). Nil = fullscreen.
        public var position: MediaPosition?
        /// Whether this item is muted (audio only)
        public var isMuted: Bool

        /// Computed end time on the timeline
        public var timelineOut: TimeInterval {
            timelineIn + duration
        }

        public init(
            id: UUID = UUID(),
            type: MediaItemType,
            path: String,
            name: String,
            timelineIn: TimeInterval,
            duration: TimeInterval,
            volume: Double = 1.0,
            opacity: Double = 1.0,
            position: MediaPosition? = nil,
            isMuted: Bool = false
        ) {
            self.id = id
            self.type = type
            self.path = path
            self.name = name
            self.timelineIn = timelineIn
            self.duration = duration
            self.volume = volume
            self.opacity = opacity
            self.position = position
            self.isMuted = isMuted
        }
    }

    /// Media item type
    public enum MediaItemType: String, Codable, Sendable {
        case image   // PNG, JPG — rendered as video frames via CALayer
        case audio   // MP3, WAV, M4A — mixed into audio composition
    }

    /// Normalized position for image overlays on the canvas
    public struct MediaPosition: Codable, Equatable, Sendable {
        public var x: Double  // 0-1 normalized
        public var y: Double  // 0-1 normalized
        public var w: Double  // 0-1 normalized width
        public var h: Double  // 0-1 normalized height

        public init(x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }

        /// Centered position with given size
        public static func centered(w: Double, h: Double) -> MediaPosition {
            MediaPosition(x: (1 - w) / 2, y: (1 - h) / 2, w: w, h: h)
        }
    }
}
