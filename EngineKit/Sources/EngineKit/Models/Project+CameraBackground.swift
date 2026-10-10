//
//  Project+CameraBackground.swift
//  EngineKit
//
//  What to do with the area behind the person in the camera layer.
//

import Foundation

extension Project {
    public struct CameraBackground: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, CaseIterable, Sendable {
            case off
            /// Blur the original background.
            case blur
            /// Replace it with a solid color.
            case color
            /// Cut it out: whatever is behind the camera layer shows through.
            case remove
        }

        public var mode: Mode
        /// Gaussian sigma for `.blur`, in camera pixels.
        public var blurRadius: Double
        /// Hex color for `.color`.
        public var colorHex: String

        public static let blurRange: ClosedRange<Double> = 4...60

        public init(mode: Mode = .off, blurRadius: Double = 24, colorHex: String = "#1C1C1E") {
            self.mode = mode
            self.blurRadius = blurRadius
            self.colorHex = colorHex
        }

        public var isActive: Bool { mode != .off }
    }
}
