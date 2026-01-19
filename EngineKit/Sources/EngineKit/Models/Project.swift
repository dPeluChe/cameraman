//
//  Project.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// Project model representing a video project
public struct Project: Codable, Equatable {
    /// Schema version for migration support
    public var schemaVersion: Int
    /// Unique identifier
    public let projectId: ProjectId
    /// Project name
    public var name: String
    /// Tags for organization
    public var tags: [String]
    /// Creation timestamp
    public let createdAt: Date
    /// Last update timestamp
    public var updatedAt: Date
    /// Source media information
    public var sources: Sources
    /// Timeline editing model
    public var timeline: Timeline
    /// Canvas layout configuration
    public var canvas: Canvas
    /// Overlays (annotations)
    public var overlays: [Overlay]
    /// Captions configuration
    public var captions: Captions?

    /// Source media tracks
    public struct Sources: Codable, Equatable {
        /// Which track is the sync reference
        public let syncReference: String
        /// Screen recording info
        public var screen: MediaTrack
        /// Camera recording info (optional)
        public var camera: MediaTrack?
        /// Audio tracks
        public var audio: AudioTracks?
        /// Telemetry data
        public var telemetry: TelemetryTracks?

        /// Media track information
        public struct MediaTrack: Codable, Equatable {
            /// Relative path to the file
            public let path: String
            /// Frame rate
            public let fps: Double
            /// Dimensions
            public let size: Size
            /// Sync offset in milliseconds
            public var syncOffsetMs: Int
            /// SHA256 checksum
            public let sha256: String
            /// File size in bytes
            public let sizeBytes: UInt64
        }

        /// Dimensions
        public struct Size: Codable, Equatable {
            public let w: Int
            public let h: Int
        }

        /// Audio tracks
        public struct AudioTracks: Codable, Equatable {
            /// System audio
            public var system: AudioTrack?
            /// Microphone audio
            public var mic: AudioTrack?

            public struct AudioTrack: Codable, Equatable {
                public let path: String
                public var syncOffsetMs: Int
                public let sha256: String
                public let sizeBytes: UInt64
            }
        }

        /// Telemetry data
        public struct TelemetryTracks: Codable, Equatable {
            public let cursor: TelemetryTrack?
            public let keys: TelemetryTrack?

            public struct TelemetryTrack: Codable, Equatable {
                public let path: String
            }
        }
    }

    /// Timeline model
    public struct Timeline: Codable, Equatable {
        /// Total duration in seconds
        public let duration: TimeInterval
        /// Timeline segments (non-destructive edits)
        public var segments: [Segment]

        /// A segment represents a portion of source media on the timeline
        public struct Segment: Codable, Equatable, Identifiable {
            public let id: String
            /// Start time in source (seconds)
            public var sourceIn: TimeInterval
            /// End time in source (seconds)
            public var sourceOut: TimeInterval
            /// Start time on timeline (seconds)
            public var timelineIn: TimeInterval
            /// Playback speed multiplier
            public var speed: Double
        }
    }

    /// Canvas configuration
    public struct Canvas: Codable, Equatable {
        /// Output format
        public let format: Format
        /// Background configuration
        public var background: Background
        /// Layout preset
        public var layout: Layout

        /// Output format specification
        public struct Format: Codable, Equatable {
            public let aspect: String
            public let w: Int
            public let h: Int
        }

        /// Background configuration
        public struct Background: Codable, Equatable {
            public let type: String
            public let value: String
            public let fitMode: String? // For image backgrounds: "fit" or "fill"
        }

        /// Layout configuration
        public struct Layout: Codable, Equatable {
            public let type: String
            public var camera: CameraPosition?

            /// Camera position for PiP/side-by-side
            public struct CameraPosition: Codable, Equatable {
                public var x: Double
                public var y: Double
                public var w: Double
                public var h: Double
                public var cornerRadius: Double
            }
        }
    }

    /// Overlay (annotation) model
    public struct Overlay: Codable, Equatable, Identifiable {
        public var id: UUID
        public var type: OverlayType
        public var start: TimeInterval
        public var end: TimeInterval
        public var transform: Transform
        public var style: Style
        public var animation: Animation?

        /// Overlay types
        public enum OverlayType: String, Codable {
            case arrow
            case rect
            case line
            case text
        }

        /// Transform (position, scale, rotation)
        public struct Transform: Codable, Equatable {
            public var x: Double
            public var y: Double
            public var scale: Double
            public var rotation: Double
        }

        /// Style configuration
        public struct Style: Codable, Equatable {
            public var stroke: String
            public var strokeWidth: Double
            public var shadow: Bool
            public var font: String?
            public var size: Double?
            public var color: String?
            public var bg: String?
            public var text: String?
        }

        /// Animation configuration
        public struct Animation: Codable, Equatable {
            /// Type of animation
            public var type: AnimationType
            /// Fade in duration in seconds
            public var fadeInDuration: TimeInterval
            /// Fade out duration in seconds
            public var fadeOutDuration: TimeInterval
            /// Draw-on animation duration (for lines, arrows, shapes)
            public var drawOnDuration: TimeInterval?
            /// Easing function for animations
            public var easing: EasingFunction

            /// Animation types
            public enum AnimationType: String, Codable {
                case none
                case fadeIn
                case fadeOut
                case fadeInOut
                case drawOn
            }

            /// Easing functions
            public enum EasingFunction: String, Codable {
                case linear
                case easeIn
                case easeOut
                case easeInOut
            }

            /// Initialize a new animation
            public init(
                type: AnimationType,
                fadeInDuration: TimeInterval = 0.3,
                fadeOutDuration: TimeInterval = 0.3,
                drawOnDuration: TimeInterval? = nil,
                easing: EasingFunction = .easeInOut
            ) {
                self.type = type
                self.fadeInDuration = fadeInDuration
                self.fadeOutDuration = fadeOutDuration
                self.drawOnDuration = drawOnDuration
                self.easing = easing
            }

            /// Default fade-in animation
            public static let fadeIn = Animation(type: .fadeIn, fadeInDuration: 0.3, fadeOutDuration: 0.3)

            /// Default fade-out animation
            public static let fadeOut = Animation(type: .fadeOut, fadeInDuration: 0.3, fadeOutDuration: 0.3)

            /// Default fade-in/out animation
            public static let fadeInOut = Animation(type: .fadeInOut, fadeInDuration: 0.3, fadeOutDuration: 0.3)

            /// Default draw-on animation (for lines, arrows)
            public static func drawOn(duration: TimeInterval = 0.5) -> Animation {
                return Animation(type: .drawOn, fadeInDuration: 0, fadeOutDuration: 0, drawOnDuration: duration)
            }
        }
    }

    /// Captions configuration
    public struct Captions: Codable, Equatable {
        public let language: String
        public let srtPath: String
        public let vttPath: String
    }
}

/// Project summary for library listing
public struct ProjectSummary: Codable, Equatable, Identifiable {
    public let id: ProjectId
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let tags: [String]
    public let duration: TimeInterval
    public let thumbnailPath: String?

    public var projectId: ProjectId {
        id
    }
}
