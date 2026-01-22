//
//  Project+Timeline.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

extension Project {
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
}
