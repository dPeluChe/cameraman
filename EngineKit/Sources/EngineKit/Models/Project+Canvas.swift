//
//  Project+Canvas.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

extension Project {
    /// Canvas configuration
    public struct Canvas: Codable, Equatable {
        /// Output format
        public var format: Format
        /// Background configuration
        public var background: Background
        /// Layout preset
        public var layout: Layout
        /// Corner radius for the video content (0–16 px)
        public var videoCornerRadius: Double
        /// Drop shadow intensity on the video content (0–1)
        public var videoShadowIntensity: Double
        /// Padding between video content and canvas edges (0–0.3 as fraction of canvas size)
        public var padding: Double

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
                public var maskShape: PiPMaskShape
                /// Border width in points (0 = no border)
                public var borderWidth: Double
                /// Border color as hex string (e.g. "#FF0000")
                public var borderColor: String

                public init(
                    x: Double,
                    y: Double,
                    w: Double,
                    h: Double,
                    cornerRadius: Double = 0,
                    maskShape: PiPMaskShape = .roundedRect,
                    borderWidth: Double = 0,
                    borderColor: String = "#FFFFFF"
                ) {
                    self.x = x
                    self.y = y
                    self.w = w
                    self.h = h
                    self.cornerRadius = cornerRadius
                    self.maskShape = maskShape
                    self.borderWidth = borderWidth
                    self.borderColor = borderColor
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    x = try container.decode(Double.self, forKey: .x)
                    y = try container.decode(Double.self, forKey: .y)
                    w = try container.decode(Double.self, forKey: .w)
                    h = try container.decode(Double.self, forKey: .h)
                    cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
                    maskShape = try container.decodeIfPresent(PiPMaskShape.self, forKey: .maskShape) ?? .roundedRect
                    borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
                    borderColor = try container.decodeIfPresent(String.self, forKey: .borderColor) ?? "#FFFFFF"
                }
            }
        }

        /// Initialize a new canvas configuration
        public init(
            format: Format,
            background: Background,
            layout: Layout,
            videoCornerRadius: Double = 0,
            videoShadowIntensity: Double = 0,
            padding: Double = 0
        ) {
            self.format = format
            self.background = background
            self.layout = layout
            self.videoCornerRadius = videoCornerRadius
            self.videoShadowIntensity = videoShadowIntensity
            self.padding = padding
        }

        /// Backward-compatible decoder for projects without new fields
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decode(Format.self, forKey: .format)
            background = try container.decode(Background.self, forKey: .background)
            layout = try container.decode(Layout.self, forKey: .layout)
            videoCornerRadius = try container.decodeIfPresent(Double.self, forKey: .videoCornerRadius) ?? 0
            videoShadowIntensity = try container.decodeIfPresent(Double.self, forKey: .videoShadowIntensity) ?? 0
            padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? 0
        }
    }
}
