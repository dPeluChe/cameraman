//
//  Project+Overlay.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

extension Project {
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
}
