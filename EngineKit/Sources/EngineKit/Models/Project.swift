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
    /// Source media information (Legacy/Migration)
    public var sources: Sources?
    /// Collection of takes (V2)
    public var takes: [Take]
    /// Timeline editing model
    public var timeline: Timeline
    /// Canvas layout configuration
    public var canvas: Canvas
    /// Overlays (annotations)
    public var overlays: [Overlay]
    /// Captions configuration
    public var captions: Captions?
    /// Chapter markers for video navigation
    public var chapters: [Chapter]

    /// Helper to access sources from V1 (legacy) or V2 (first take)
    public var primarySources: Sources? {
        sources ?? takes.first?.sources
    }

    public init(
        projectId: ProjectId,
        name: String,
        sources: Sources? = nil,
        takes: [Take] = [],
        timeline: Timeline,
        canvas: Canvas,
        overlays: [Overlay] = [],
        chapters: [Chapter] = [],
        captions: Captions? = nil,
        tags: [String] = [],
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.projectId = projectId
        self.name = name
        self.sources = sources
        self.takes = takes
        self.timeline = timeline
        self.canvas = canvas
        self.overlays = overlays
        self.chapters = chapters
        self.captions = captions
        self.tags = tags
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A Take represents a single recording session containing multiple media sources (screen, camera, mic, etc.)
    public struct Take: Codable, Equatable, Identifiable {
        public let id: UUID
        public var name: String
        public let createdAt: Date
        public var sources: Sources
        
        public init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            sources: Sources
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.sources = sources
        }
    }

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

        public init(
            syncReference: String = "screen",
            screen: MediaTrack,
            camera: MediaTrack? = nil,
            audio: AudioTracks? = nil,
            telemetry: TelemetryTracks? = nil
        ) {
            self.syncReference = syncReference
            self.screen = screen
            self.camera = camera
            self.audio = audio
            self.telemetry = telemetry
        }

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

            public init(
                path: String,
                fps: Double,
                size: Size,
                syncOffsetMs: Int = 0,
                sha256: String = "",
                sizeBytes: UInt64 = 0
            ) {
                self.path = path
                self.fps = fps
                self.size = size
                self.syncOffsetMs = syncOffsetMs
                self.sha256 = sha256
                self.sizeBytes = sizeBytes
            }
        }

        /// Dimensions
        public struct Size: Codable, Equatable {
            public let w: Int
            public let h: Int

            public init(w: Int, h: Int) {
                self.w = w
                self.h = h
            }
        }

        /// Audio tracks
        public struct AudioTracks: Codable, Equatable {
            /// System audio
            public var system: AudioTrack?
            /// Microphone audio
            public var mic: AudioTrack?

            public init(system: AudioTrack? = nil, mic: AudioTrack? = nil) {
                self.system = system
                self.mic = mic
            }

            public struct AudioTrack: Codable, Equatable {
                public let path: String
                public var syncOffsetMs: Int
                public let sha256: String
                public let sizeBytes: UInt64

                public init(
                    path: String,
                    syncOffsetMs: Int = 0,
                    sha256: String = "",
                    sizeBytes: UInt64 = 0
                ) {
                    self.path = path
                    self.syncOffsetMs = syncOffsetMs
                    self.sha256 = sha256
                    self.sizeBytes = sizeBytes
                }
            }
        }

        /// Telemetry data
        public struct TelemetryTracks: Codable, Equatable {
            public let cursor: TelemetryTrack?
            public let keys: TelemetryTrack?

            public init(cursor: TelemetryTrack? = nil, keys: TelemetryTrack? = nil) {
                self.cursor = cursor
                self.keys = keys
            }

            public struct TelemetryTrack: Codable, Equatable {
                public let path: String

                public init(path: String) {
                    self.path = path
                }
            }
        }
    }

    /// Timeline model
    public struct Timeline: Codable, Equatable {
        /// Total duration in seconds
        public let duration: TimeInterval
        /// Timeline segments (non-destructive edits)
        public var segments: [Segment]

        public init(duration: TimeInterval, segments: [Segment]) {
            self.duration = duration
            self.segments = segments
        }

        /// A segment represents a portion of source media on the timeline
        public struct Segment: Codable, Equatable, Identifiable {
            public let id: String
            /// ID of the take this segment refers to (if nil, assumes the first/legacy take)
            public var takeId: UUID?
            /// Start time in source (seconds)
            public var sourceIn: TimeInterval
            /// End time in source (seconds)
            public var sourceOut: TimeInterval
            /// Start time on timeline (seconds)
            public var timelineIn: TimeInterval
            /// Playback speed multiplier
            public var speed: Double
            /// Zoom configuration for this segment (optional, overrides project defaults)
            public var zoom: ZoomConfiguration?

            public init(
                id: String = UUID().uuidString,
                takeId: UUID? = nil,
                sourceIn: TimeInterval,
                sourceOut: TimeInterval,
                timelineIn: TimeInterval,
                speed: Double = 1.0,
                zoom: ZoomConfiguration? = nil
            ) {
                self.id = id
                self.takeId = takeId
                self.sourceIn = sourceIn
                self.sourceOut = sourceOut
                self.timelineIn = timelineIn
                self.speed = speed
                self.zoom = zoom
            }
        }

        /// Zoom configuration for a timeline segment
        public struct ZoomConfiguration: Codable, Equatable {
            /// Whether zoom is enabled for this segment
            public let enabled: Bool
            /// Minimum zoom level (1.0 = no zoom)
            public let minZoomLevel: Double
            /// Maximum zoom level (2.0 = 2x zoom)
            public let maxZoomLevel: Double
            /// Zoom intensity preset (optional shorthand)
            public let intensity: ZoomIntensity?

            /// Zoom intensity presets
            public enum ZoomIntensity: String, Codable {
                case disabled
                case subtle
                case normal
                case aggressive

                /// Convert to ZoomPlanGenerator.Configuration
                public func toConfiguration(base: ZoomPlanGenerator.Configuration) -> ZoomPlanGenerator.Configuration {
                    switch self {
                    case .disabled:
                        return ZoomPlanGenerator.Configuration(
                            minZoomLevel: base.minZoomLevel,
                            maxZoomLevel: base.maxZoomLevel,
                            defaultZoomLevel: base.defaultZoomLevel,
                            zoomInDuration: base.zoomInDuration,
                            zoomOutDuration: base.zoomOutDuration,
                            holdDuration: base.holdDuration,
                            boundingBoxPadding: base.boundingBoxPadding,
                            easingFunction: base.easingFunction,
                            maxZoomsPerMinute: base.maxZoomsPerMinute,
                            minTimeBetweenZooms: base.minTimeBetweenZooms,
                            zoomEnabled: false
                        )
                    case .subtle:
                        return ZoomPlanGenerator.Configuration.subtle()
                    case .normal:
                        return ZoomPlanGenerator.Configuration.default()
                    case .aggressive:
                        return ZoomPlanGenerator.Configuration.aggressive()
                    }
                }
            }

            /// Create a zoom configuration
            public init(
                enabled: Bool = true,
                minZoomLevel: Double = 1.0,
                maxZoomLevel: Double = 2.5,
                intensity: ZoomIntensity? = nil
            ) {
                self.enabled = enabled
                self.minZoomLevel = minZoomLevel
                self.maxZoomLevel = maxZoomLevel
                self.intensity = intensity
            }

            /// Disabled zoom configuration
            public static let disabled = ZoomConfiguration(enabled: false)

            /// Subtle zoom configuration
            public static let subtle = ZoomConfiguration(intensity: .subtle)

            /// Normal zoom configuration (default)
            public static let normal = ZoomConfiguration(intensity: .normal)

            /// Aggressive zoom configuration
            public static let aggressive = ZoomConfiguration(intensity: .aggressive)
        }
    }

    /// Canvas configuration
    public struct Canvas: Codable, Equatable {
        /// Output format
        public var format: Format
        /// Background configuration
        public var background: Background
        /// Layout preset
        public var layout: Layout

        /// Output format specification
        public struct Format: Codable, Equatable {
            public var aspect: String
            public var w: Int
            public var h: Int

            /// Initialize a new format specification
            public init(
                aspect: String,
                w: Int,
                h: Int
            ) {
                self.aspect = aspect
                self.w = w
                self.h = h
            }
        }

        /// Background configuration
        public struct Background: Codable, Equatable {
            public let type: String
            public let value: String
            public let fitMode: String? // For image backgrounds: "fit" or "fill"

            /// Initialize a new background configuration
            public init(
                type: String,
                value: String,
                fitMode: String? = nil
            ) {
                self.type = type
                self.value = value
                self.fitMode = fitMode
            }
        }

        /// Layout configuration
        public struct Layout: Codable, Equatable {
            public let type: String
            public var camera: CameraPosition?

            /// Initialize a new layout configuration
            public init(
                type: String,
                camera: CameraPosition? = nil
            ) {
                self.type = type
                self.camera = camera
            }

            /// Camera position for PiP/side-by-side
            public struct CameraPosition: Codable, Equatable {
                public var x: Double
                public var y: Double
                public var w: Double
                public var h: Double
                public var cornerRadius: Double

                /// Initialize a new camera position
                public init(
                    x: Double,
                    y: Double,
                    w: Double,
                    h: Double,
                    cornerRadius: Double = 0
                ) {
                    self.x = x
                    self.y = y
                    self.w = w
                    self.h = h
                    self.cornerRadius = cornerRadius
                }
            }
        }

        /// Initialize a new canvas configuration
        public init(
            format: Format,
            background: Background,
            layout: Layout
        ) {
            self.format = format
            self.background = background
            self.layout = layout
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

        /// Initialize a new overlay
        public init(
            id: UUID,
            type: OverlayType,
            start: TimeInterval,
            end: TimeInterval,
            transform: Transform,
            style: Style,
            animation: Animation?
        ) {
            self.id = id
            self.type = type
            self.start = start
            self.end = end
            self.transform = transform
            self.style = style
            self.animation = animation
        }

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

            /// Initialize a new transform
            public init(
                x: Double = 0,
                y: Double = 0,
                scale: Double = 1,
                rotation: Double = 0
            ) {
                self.x = x
                self.y = y
                self.scale = scale
                self.rotation = rotation
            }
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

            /// Initialize a new style
            public init(
                stroke: String,
                strokeWidth: Double,
                shadow: Bool,
                font: String? = nil,
                size: Double? = nil,
                color: String? = nil,
                bg: String? = nil,
                text: String? = nil
            ) {
                self.stroke = stroke
                self.strokeWidth = strokeWidth
                self.shadow = shadow
                self.font = font
                self.size = size
                self.color = color
                self.bg = bg
                self.text = text
            }
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

    /// Chapter marker for video navigation
    public struct Chapter: Codable, Equatable, Identifiable {
        /// Unique identifier
        public let id: UUID
        /// Chapter title (editable by user)
        public var title: String
        /// Chapter start time in seconds
        public let startTime: TimeInterval
        /// Chapter end time in seconds
        public let endTime: TimeInterval
        /// Optional chapter summary
        public var summary: String?
        /// Optional keywords for the chapter
        public var keywords: [String]
        /// Timestamp when chapter was created
        public let createdAt: Date

        /// Initialize a new chapter
        public init(
            id: UUID = UUID(),
            title: String,
            startTime: TimeInterval,
            endTime: TimeInterval,
            summary: String? = nil,
            keywords: [String] = [],
            createdAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.startTime = startTime
            self.endTime = endTime
            self.summary = summary
            self.keywords = keywords
            self.createdAt = createdAt
        }

        /// Chapter duration
        public var duration: TimeInterval {
            endTime - startTime
        }
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

    public init(
        projectId: ProjectId,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String],
        duration: TimeInterval,
        thumbnailPath: String?
    ) {
        self.id = projectId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.duration = duration
        self.thumbnailPath = thumbnailPath
    }
}
