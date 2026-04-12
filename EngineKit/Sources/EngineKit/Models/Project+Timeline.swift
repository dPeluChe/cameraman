//
//  Project+Timeline.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//
//  Multi-track timeline model with backward-compatible segments accessor.
//

import Foundation

extension Project {
    /// Timeline model — multi-track architecture
    public struct Timeline: Codable, Equatable {
        /// Total duration in seconds (max end time across all tracks)
        public var duration: TimeInterval
        /// Ordered list of tracks in the timeline
        public var tracks: [TimelineTrack]

        public init(duration: TimeInterval, tracks: [TimelineTrack] = []) {
            self.duration = duration
            self.tracks = tracks
        }

        /// Convenience initializer from segments (creates a primary track)
        public init(duration: TimeInterval, segments: [Segment]) {
            self.duration = duration
            let clips = segments.map { TimelineClip.fromSegment($0) }
            self.tracks = [TimelineTrack(id: TimelineTrack.primaryTrackId, type: .primary, clips: clips)]
        }

        // MARK: - Codable (migrates old segments format → tracks)

        enum CodingKeys: String, CodingKey {
            case duration
            case tracks
            case segments // legacy key for migration
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            duration = try container.decode(TimeInterval.self, forKey: .duration)

            if let tracks = try container.decodeIfPresent([TimelineTrack].self, forKey: .tracks) {
                self.tracks = tracks
            } else if let legacySegments = try container.decodeIfPresent([Segment].self, forKey: .segments) {
                // Migration: convert flat segments into a primary track
                let clips = legacySegments.map { TimelineClip.fromSegment($0) }
                self.tracks = [TimelineTrack(id: TimelineTrack.primaryTrackId, type: .primary, clips: clips)]
            } else {
                self.tracks = []
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(duration, forKey: .duration)
            try container.encode(tracks, forKey: .tracks)
        }

        // MARK: - Track Accessors

        /// The primary recording track (always exists, created on first access if needed)
        public var primaryTrack: TimelineTrack? {
            tracks.first(where: { $0.type == .primary })
        }

        /// Index of the primary track
        public var primaryTrackIndex: Int? {
            tracks.firstIndex(where: { $0.type == .primary })
        }

        /// All video overlay tracks (B-roll, images, slides)
        public var videoTracks: [TimelineTrack] {
            tracks.filter { $0.type == .video }
        }

        /// All audio tracks (music, effects)
        public var audioTracks: [TimelineTrack] {
            tracks.filter { $0.type == .audio }
        }

        /// Ensure a primary track exists, creating one if needed
        public mutating func ensurePrimaryTrack() {
            if primaryTrack == nil {
                tracks.insert(TimelineTrack(id: TimelineTrack.primaryTrackId, type: .primary), at: 0)
            }
        }

        /// Add a new track and return its ID
        @discardableResult
        public mutating func addTrack(type: TrackType, name: String = "") -> UUID {
            let track = TimelineTrack(name: name, type: type)
            tracks.append(track)
            return track.id
        }

        // MARK: - Backward-Compatible Segments Accessor

        /// Recording segments from the primary track.
        /// Getter: Converts primary track clips back to legacy Segment format.
        /// Setter: Converts legacy Segments into primary track clips.
        public var segments: [Segment] {
            get {
                guard let primary = primaryTrack else { return [] }
                return primary.clips.compactMap { clip -> Segment? in
                    guard case .recording(let ref) = clip.content else { return nil }
                    return Segment(
                        id: clip.id,
                        takeId: ref.takeId,
                        sourceIn: ref.sourceIn,
                        sourceOut: ref.sourceOut,
                        timelineIn: clip.timelineIn,
                        speed: clip.speed,
                        zoom: ref.zoom,
                        cameraPosition: ref.cameraPosition,
                        volume: clip.volume,
                        audioMuted: ref.audioMuted
                    )
                }
            }
            set {
                let newRecordingClips = newValue.map { TimelineClip.fromSegment($0) }
                if let idx = primaryTrackIndex {
                    // Preserve non-recording clips (images, colors, videos)
                    let nonRecordingClips = tracks[idx].clips.filter { !$0.isRecording }
                    tracks[idx].clips = (newRecordingClips + nonRecordingClips)
                        .sorted { $0.timelineIn < $1.timelineIn }
                } else {
                    tracks.insert(
                        TimelineTrack(id: TimelineTrack.primaryTrackId, type: .primary, clips: newRecordingClips),
                        at: 0
                    )
                }
            }
        }

        /// A segment represents a portion of source media on the timeline (legacy compat)
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
            /// Per-segment camera position override (nil = use project.canvas.layout.camera)
            public var cameraPosition: Project.Canvas.Layout.CameraPosition?
            /// Per-segment volume override (nil = use global, range 0.0–3.0)
            public var volume: Double?
            /// Per-segment audio mute (nil = use global)
            public var audioMuted: Bool?

            public init(
                id: String = UUID().uuidString,
                takeId: UUID? = nil,
                sourceIn: TimeInterval,
                sourceOut: TimeInterval,
                timelineIn: TimeInterval,
                speed: Double = 1.0,
                zoom: ZoomConfiguration? = nil,
                cameraPosition: Project.Canvas.Layout.CameraPosition? = nil,
                volume: Double? = nil,
                audioMuted: Bool? = nil
            ) {
                self.id = id
                self.takeId = takeId
                self.sourceIn = sourceIn
                self.sourceOut = sourceOut
                self.timelineIn = timelineIn
                self.speed = speed
                self.zoom = zoom
                self.cameraPosition = cameraPosition
                self.volume = volume
                self.audioMuted = audioMuted
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                takeId = try container.decodeIfPresent(UUID.self, forKey: .takeId)
                sourceIn = try container.decode(TimeInterval.self, forKey: .sourceIn)
                sourceOut = try container.decode(TimeInterval.self, forKey: .sourceOut)
                timelineIn = try container.decode(TimeInterval.self, forKey: .timelineIn)
                speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
                zoom = try container.decodeIfPresent(ZoomConfiguration.self, forKey: .zoom)
                cameraPosition = try container.decodeIfPresent(Project.Canvas.Layout.CameraPosition.self, forKey: .cameraPosition)
                volume = try container.decodeIfPresent(Double.self, forKey: .volume)
                audioMuted = try container.decodeIfPresent(Bool.self, forKey: .audioMuted)
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
}
