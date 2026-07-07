//
//  Project+SyntheticCursor.swift
//  EngineKit
//
//  Persisted toggle/style for synthetic cursor rendering. The actual cursor
//  path (`CursorPlan`) is derived from telemetry on demand (like `ZoomPlan`),
//  not stored on the project.
//

import Foundation

extension Project {
    /// Synthetic cursor rendering settings.
    public struct SyntheticCursorConfig: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// Cursor dot diameter multiplier (1.0 = default size).
        public var scale: Double
        /// Cursor fill color, hex (e.g. "#FFFFFF").
        public var color: String
        /// Whether to draw an expanding ring on clicks.
        public var rippleEnabled: Bool

        public init(
            enabled: Bool = false,
            scale: Double = 1.0,
            color: String = "#FFFFFF",
            rippleEnabled: Bool = true
        ) {
            self.enabled = enabled
            self.scale = scale
            self.color = color
            self.rippleEnabled = rippleEnabled
        }

        public static let `default` = SyntheticCursorConfig()
    }
}
