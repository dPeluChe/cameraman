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

                /// Initialize a new camera position
                public init(
                    x: Double,
                    y: Double,
                    w: Double,
                    h: Double,
                    cornerRadius: Double = 0,
                    maskShape: PiPMaskShape = .roundedRect
                ) {
                    self.x = x
                    self.y = y
                    self.w = w
                    self.h = h
                    self.cornerRadius = cornerRadius
                    self.maskShape = maskShape
                }

                /// Custom decoder to handle old projects without maskShape field
                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    x = try container.decode(Double.self, forKey: .x)
                    y = try container.decode(Double.self, forKey: .y)
                    w = try container.decode(Double.self, forKey: .w)
                    h = try container.decode(Double.self, forKey: .h)
                    cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
                    maskShape = try container.decodeIfPresent(PiPMaskShape.self, forKey: .maskShape) ?? .roundedRect
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
}
