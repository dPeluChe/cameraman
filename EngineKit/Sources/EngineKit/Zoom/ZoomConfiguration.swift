//
//  ZoomConfiguration.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

extension ZoomPlanGenerator {
    /// Configuration for zoom plan generation
    public struct Configuration: Equatable, Sendable {
        /// Minimum zoom level (1.0 = no zoom)
        /// Default: 1.0 - no zoom out beyond original
        public let minZoomLevel: Double

        /// Maximum zoom level (2.0 = 2x zoom, 3.0 = 3x zoom)
        /// Default: 2.5 - reasonable zoom that doesn't disorient viewers
        public let maxZoomLevel: Double

        /// Default zoom level when not actively zooming
        /// Default: 1.0 - no zoom
        public let defaultZoomLevel: Double

        /// Duration of zoom-in animation (seconds)
        /// Default: 0.5 seconds - smooth but responsive
        public let zoomInDuration: TimeInterval

        /// Duration of zoom-out animation (seconds)
        /// Default: 0.7 seconds - slightly slower for smoother return
        public let zoomOutDuration: TimeInterval

        /// Duration to hold zoom before releasing (seconds)
        /// Default: 1.0 seconds - gives viewers time to see zoomed content
        public let holdDuration: TimeInterval

        /// Padding around click bounding box (percentage, 0.0-1.0)
        /// Default: 0.15 (15% padding) - ensures cursor/element isn't at edge
        public let boundingBoxPadding: Double

        /// Easing function for zoom animations
        /// Default: easeInOut - smooth acceleration and deceleration
        public let easingFunction: EasingFunction

        /// Maximum number of zoom events per minute (prevents excessive zooming)
        /// Default: 6 zooms per minute - avoids disorienting viewers
        public let maxZoomsPerMinute: Int

        /// Minimum time between zoom events (seconds)
        /// Default: 3.0 seconds - prevents rapid zoom in/out
        public let minTimeBetweenZooms: TimeInterval

        /// Whether to enable zoom (can be toggled per section)
        /// Default: true
        public let zoomEnabled: Bool

        public init(
            minZoomLevel: Double = 1.0,
            maxZoomLevel: Double = 2.5,
            defaultZoomLevel: Double = 1.0,
            zoomInDuration: TimeInterval = 0.5,
            zoomOutDuration: TimeInterval = 0.7,
            holdDuration: TimeInterval = 1.0,
            boundingBoxPadding: Double = 0.15,
            easingFunction: EasingFunction = .easeInOut,
            maxZoomsPerMinute: Int = 6,
            minTimeBetweenZooms: TimeInterval = 3.0,
            zoomEnabled: Bool = true
        ) {
            self.minZoomLevel = minZoomLevel
            self.maxZoomLevel = maxZoomLevel
            self.defaultZoomLevel = defaultZoomLevel
            self.zoomInDuration = zoomInDuration
            self.zoomOutDuration = zoomOutDuration
            self.holdDuration = holdDuration
            self.boundingBoxPadding = boundingBoxPadding
            self.easingFunction = easingFunction
            self.maxZoomsPerMinute = maxZoomsPerMinute
            self.minTimeBetweenZooms = minTimeBetweenZooms
            self.zoomEnabled = zoomEnabled
        }

        /// Validate configuration values
        public func validate() throws {
            guard minZoomLevel >= 1.0 else {
                throw ZoomPlanError.invalidConfiguration("minZoomLevel must be >= 1.0 (no zoom out)")
            }
            guard maxZoomLevel > minZoomLevel else {
                throw ZoomPlanError.invalidConfiguration("maxZoomLevel must be > minZoomLevel")
            }
            guard maxZoomLevel <= 5.0 else {
                throw ZoomPlanError.invalidConfiguration("maxZoomLevel must be <= 5.0 (5x zoom max to prevent disorientation)")
            }
            guard defaultZoomLevel >= minZoomLevel && defaultZoomLevel <= maxZoomLevel else {
                throw ZoomPlanError.invalidConfiguration("defaultZoomLevel must be between minZoomLevel and maxZoomLevel")
            }
            guard zoomInDuration > 0 && zoomInDuration <= 2.0 else {
                throw ZoomPlanError.invalidConfiguration("zoomInDuration must be between 0 and 2 seconds")
            }
            guard zoomOutDuration > 0 && zoomOutDuration <= 2.0 else {
                throw ZoomPlanError.invalidConfiguration("zoomOutDuration must be between 0 and 2 seconds")
            }
            guard holdDuration >= 0 && holdDuration <= 5.0 else {
                throw ZoomPlanError.invalidConfiguration("holdDuration must be between 0 and 5 seconds")
            }
            guard boundingBoxPadding >= 0 && boundingBoxPadding <= 0.5 else {
                throw ZoomPlanError.invalidConfiguration("boundingBoxPadding must be between 0 and 0.5 (50%)")
            }
            guard maxZoomsPerMinute > 0 && maxZoomsPerMinute <= 20 else {
                throw ZoomPlanError.invalidConfiguration("maxZoomsPerMinute must be between 1 and 20")
            }
            guard minTimeBetweenZooms >= 1.0 && minTimeBetweenZooms <= 10.0 else {
                throw ZoomPlanError.invalidConfiguration("minTimeBetweenZooms must be between 1 and 10 seconds")
            }
        }

        /// Default configuration for tutorial/demo recordings
        public static func `default`() -> Configuration {
            return Configuration()
        }

        /// Subtle configuration - minimal zoom, slower transitions
        public static func subtle() -> Configuration {
            return Configuration(
                minZoomLevel: 1.0,
                maxZoomLevel: 1.8,
                defaultZoomLevel: 1.0,
                zoomInDuration: 0.8,
                zoomOutDuration: 1.0,
                holdDuration: 1.5,
                boundingBoxPadding: 0.2,
                easingFunction: .easeInOut,
                maxZoomsPerMinute: 4,
                minTimeBetweenZooms: 5.0,
                zoomEnabled: true
            )
        }

        /// Aggressive configuration - more zoom, faster transitions
        public static func aggressive() -> Configuration {
            return Configuration(
                minZoomLevel: 1.0,
                maxZoomLevel: 3.5,
                defaultZoomLevel: 1.0,
                zoomInDuration: 0.3,
                zoomOutDuration: 0.5,
                holdDuration: 0.5,
                boundingBoxPadding: 0.1,
                easingFunction: .easeOut,
                maxZoomsPerMinute: 10,
                minTimeBetweenZooms: 2.0,
                zoomEnabled: true
            )
        }

        /// Disabled zoom - no zoom events generated
        public static func disabled() -> Configuration {
            return Configuration(
                zoomEnabled: false
            )
        }
    }
}
