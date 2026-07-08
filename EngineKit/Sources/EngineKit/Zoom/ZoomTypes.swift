//
//  ZoomTypes.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import CoreGraphics

extension ZoomPlanGenerator {
    /// A single zoom keyframe
    public struct ZoomKeyframe: Codable, Identifiable, Equatable, Sendable {
        /// Unique identifier
        public let id: UUID
        /// Timestamp in seconds from recording start
        public var timestamp: TimeInterval
        /// Zoom level at this keyframe (1.0 = no zoom, 2.0 = 2x zoom)
        public var zoomLevel: Double
        /// Focus point X (normalized 0.0-1.0, 0.5 = center)
        public var focusX: Double
        /// Focus point Y (normalized 0.0-1.0, 0.5 = center)
        public var focusY: Double
        /// Easing function to use for transition to next keyframe
        public var easing: EasingFunction
        /// Whether this keyframe was created manually by the user (vs auto-generated)
        public var isManual: Bool

        public init(
            id: UUID = UUID(),
            timestamp: TimeInterval,
            zoomLevel: Double,
            focusX: Double,
            focusY: Double,
            easing: EasingFunction = .easeInOut,
            isManual: Bool = false
        ) {
            self.id = id
            self.timestamp = timestamp
            self.zoomLevel = zoomLevel
            self.focusX = focusX
            self.focusY = focusY
            self.easing = easing
            self.isManual = isManual
        }

        enum CodingKeys: String, CodingKey {
            case id, timestamp, zoomLevel, focusX, focusY, easing, isManual
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            timestamp = try c.decode(TimeInterval.self, forKey: .timestamp)
            zoomLevel = try c.decode(Double.self, forKey: .zoomLevel)
            focusX = try c.decode(Double.self, forKey: .focusX)
            focusY = try c.decode(Double.self, forKey: .focusY)
            easing = try c.decode(EasingFunction.self, forKey: .easing)
            isManual = try c.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
        }
    }

    /// A zoom event representing a complete zoom-in, hold, and zoom-out cycle
    public struct ZoomEvent: Identifiable, Codable, Equatable, Sendable {
        /// Unique identifier
        public let id: UUID
        /// Zoom-in start timestamp
        public let zoomInStartTime: TimeInterval
        /// Zoom-in end timestamp (zoom level reached)
        public let zoomInEndTime: TimeInterval
        /// Hold end timestamp (start zooming out)
        public let holdEndTime: TimeInterval
        /// Zoom-out end timestamp (back to default zoom)
        public let zoomOutEndTime: TimeInterval
        /// Target zoom level
        public let targetZoomLevel: Double
        /// Focus point X (normalized 0.0-1.0)
        public let focusX: Double
        /// Focus point Y (normalized 0.0-1.0)
        public let focusY: Double
        /// Click window that triggered this zoom
        public let clickWindowId: UUID
        /// Easing function for zoom transitions
        public let easing: EasingFunction

        /// Total duration of this zoom event
        public var totalDuration: TimeInterval {
            return zoomOutEndTime - zoomInStartTime
        }

        /// Zoom-in duration
        public var zoomInDuration: TimeInterval {
            return zoomInEndTime - zoomInStartTime
        }

        /// Hold duration
        public var holdDuration: TimeInterval {
            return holdEndTime - zoomInEndTime
        }

        /// Zoom-out duration
        public var zoomOutDuration: TimeInterval {
            return zoomOutEndTime - holdEndTime
        }

        public init(
            id: UUID = UUID(),
            zoomInStartTime: TimeInterval,
            zoomInEndTime: TimeInterval,
            holdEndTime: TimeInterval,
            zoomOutEndTime: TimeInterval,
            targetZoomLevel: Double,
            focusX: Double,
            focusY: Double,
            clickWindowId: UUID,
            easing: EasingFunction = .easeInOut
        ) {
            self.id = id
            self.zoomInStartTime = zoomInStartTime
            self.zoomInEndTime = zoomInEndTime
            self.holdEndTime = holdEndTime
            self.zoomOutEndTime = zoomOutEndTime
            self.targetZoomLevel = targetZoomLevel
            self.focusX = focusX
            self.focusY = focusY
            self.clickWindowId = clickWindowId
            self.easing = easing
        }

        /// Generate keyframes for this zoom event
        public func generateKeyframes(defaultZoomLevel: Double) -> [ZoomKeyframe] {
            let keyframeId = UUID()

            // Keyframe 1: Start zoom-in (at default zoom level)
            let startKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomInStartTime,
                zoomLevel: defaultZoomLevel,
                focusX: 0.5, // Center focus at start
                focusY: 0.5,
                easing: easing
            )

            // Keyframe 2: End zoom-in / Start hold (at target zoom level)
            let zoomInKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomInEndTime,
                zoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                easing: .linear // No easing during hold
            )

            // Keyframe 3: End hold / Start zoom-out (still at target zoom level)
            let holdKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: holdEndTime,
                zoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                easing: easing
            )

            // Keyframe 4: End zoom-out (back to default zoom level)
            let zoomOutKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomOutEndTime,
                zoomLevel: defaultZoomLevel,
                focusX: 0.5, // Return to center focus
                focusY: 0.5,
                easing: .linear // No easing after zoom-out
            )

            return [startKeyframe, zoomInKeyframe, holdKeyframe, zoomOutKeyframe]
        }
    }

    /// Complete zoom plan with all zoom events and keyframes
    public struct ZoomPlan: Equatable, Sendable {
        /// All zoom events in chronological order
        public let events: [ZoomEvent]
        /// All keyframes in chronological order (merged from all events)
        public let keyframes: [ZoomKeyframe]
        /// Configuration used to generate this plan
        public let configuration: Configuration
        /// Statistics about the zoom plan
        public let stats: ZoomPlanStats

        public init(
            events: [ZoomEvent],
            keyframes: [ZoomKeyframe],
            configuration: Configuration,
            stats: ZoomPlanStats
        ) {
            self.events = events
            self.keyframes = keyframes
            self.configuration = configuration
            self.stats = stats
        }

        /// Get zoom level at a specific timestamp (interpolated between keyframes)
        public func zoomLevel(at timestamp: TimeInterval) -> Double {
            guard !keyframes.isEmpty else { return configuration.defaultZoomLevel }

            // Find surrounding keyframes
            var previousKeyframe: ZoomKeyframe?
            var nextKeyframe: ZoomKeyframe?

            for keyframe in keyframes {
                if keyframe.timestamp <= timestamp {
                    previousKeyframe = keyframe
                } else if keyframe.timestamp > timestamp && nextKeyframe == nil {
                    nextKeyframe = keyframe
                    break
                }
            }

            // Handle edge cases
            guard let prev = previousKeyframe else {
                // Before first keyframe: no zoom applied yet
                return configuration.defaultZoomLevel
            }

            guard let next = nextKeyframe else {
                // After last keyframe
                return prev.zoomLevel
            }

            // Interpolate between keyframes
            let duration = next.timestamp - prev.timestamp
            guard duration > 0 else { return prev.zoomLevel }

            let progress = (timestamp - prev.timestamp) / duration
            let easedProgress = prev.easing.apply(to: progress)

            let zoomDelta = next.zoomLevel - prev.zoomLevel
            return prev.zoomLevel + (zoomDelta * easedProgress)
        }

        /// Get focus point at a specific timestamp (interpolated between keyframes)
        public func focusPoint(at timestamp: TimeInterval) -> CGPoint {
            guard !keyframes.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }

            // Find surrounding keyframes
            var previousKeyframe: ZoomKeyframe?
            var nextKeyframe: ZoomKeyframe?

            for keyframe in keyframes {
                if keyframe.timestamp <= timestamp {
                    previousKeyframe = keyframe
                } else if keyframe.timestamp > timestamp && nextKeyframe == nil {
                    nextKeyframe = keyframe
                    break
                }
            }

            // Handle edge cases
            guard let prev = previousKeyframe else {
                // Before first keyframe: center focus, no zoom
                return CGPoint(x: 0.5, y: 0.5)
            }

            guard let next = nextKeyframe else {
                return CGPoint(x: prev.focusX, y: prev.focusY)
            }

            // Interpolate between keyframes
            let duration = next.timestamp - prev.timestamp
            guard duration > 0 else { return CGPoint(x: prev.focusX, y: prev.focusY) }

            let progress = (timestamp - prev.timestamp) / duration
            let easedProgress = prev.easing.apply(to: progress)

            let focusXDelta = next.focusX - prev.focusX
            let focusYDelta = next.focusY - prev.focusY

            return CGPoint(
                x: prev.focusX + (focusXDelta * easedProgress),
                y: prev.focusY + (focusYDelta * easedProgress)
            )
        }
    }

    /// Statistics about a zoom plan
    public struct ZoomPlanStats: Codable, Equatable, Sendable {
        /// Total number of zoom events
        public let totalZoomEvents: Int
        /// Total number of keyframes
        public let totalKeyframes: Int
        /// Total time spent zoomed in (seconds)
        public let totalZoomedTime: TimeInterval
        /// Percentage of time spent zoomed
        public let zoomedTimePercentage: Double
        /// Average zoom level
        public let averageZoomLevel: Double
        /// Maximum zoom level reached
        public let maximumZoomLevel: Double
        /// Average time between zoom events
        public let averageTimeBetweenZooms: TimeInterval
        /// Zooms per minute
        public let zoomsPerMinute: Double
        /// Time range covered by zoom plan
        public let timeRange: ClosedRange<TimeInterval>

        public init(
            totalZoomEvents: Int,
            totalKeyframes: Int,
            totalZoomedTime: TimeInterval,
            zoomedTimePercentage: Double,
            averageZoomLevel: Double,
            maximumZoomLevel: Double,
            averageTimeBetweenZooms: TimeInterval,
            zoomsPerMinute: Double,
            timeRange: ClosedRange<TimeInterval>
        ) {
            self.totalZoomEvents = totalZoomEvents
            self.totalKeyframes = totalKeyframes
            self.totalZoomedTime = totalZoomedTime
            self.zoomedTimePercentage = zoomedTimePercentage
            self.averageZoomLevel = averageZoomLevel
            self.maximumZoomLevel = maximumZoomLevel
            self.averageTimeBetweenZooms = averageTimeBetweenZooms
            self.zoomsPerMinute = zoomsPerMinute
            self.timeRange = timeRange
        }
    }

    /// Zoom plan generation errors
    public enum ZoomPlanError: LocalizedError, Equatable {
        case invalidConfiguration(String)
        case noClickWindows
        case invalidClickWindows
        case zoomRateExceeded(Int, Int) // actual, maximum
        case invalidTimeline

        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return "Invalid zoom configuration: \(message)"
            case .noClickWindows:
                return "No click windows provided for zoom plan generation"
            case .invalidClickWindows:
                return "Invalid click windows data"
            case .zoomRateExceeded(let actual, let maximum):
                return "Zoom rate exceeded: \(actual) zooms/minute exceeds maximum of \(maximum)"
            case .invalidTimeline:
                return "Invalid timeline data for zoom plan"
            }
        }

        public static func == (lhs: ZoomPlanError, rhs: ZoomPlanError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidConfiguration(let lhsMsg), .invalidConfiguration(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.noClickWindows, .noClickWindows):
                return true
            case (.invalidClickWindows, .invalidClickWindows):
                return true
            case (.zoomRateExceeded(let lhsActual, let lhsMax), .zoomRateExceeded(let rhsActual, let rhsMax)):
                return lhsActual == rhsActual && lhsMax == rhsMax
            case (.invalidTimeline, .invalidTimeline):
                return true
            default:
                return false
            }
        }
    }
}
