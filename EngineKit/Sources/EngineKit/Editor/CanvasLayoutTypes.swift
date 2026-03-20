//
//  CanvasLayoutTypes.swift
//  EngineKit
//
//  Extracted from CanvasLayout.swift — enums and error types
//

import Foundation

extension CanvasLayout {
    /// Available layout presets
    public enum LayoutPreset: String, Codable, Sendable, CaseIterable {
        case pip = "pip"
        case sideBySide = "side-by-side"
        case fullscreen = "fullscreen"
        case cinematic = "cinematic"

        /// Display name for the preset
        public var displayName: String {
            switch self {
            case .pip:
                return "Picture-in-Picture"
            case .sideBySide:
                return "Side-by-Side"
            case .fullscreen:
                return "Fullscreen"
            case .cinematic:
                return "Cinematic"
            }
        }

        /// Description of the preset
        public var description: String {
            switch self {
            case .pip:
                return "Camera in corner overlay"
            case .sideBySide:
                return "Screen and camera side by side"
            case .fullscreen:
                return "Screen content only"
            case .cinematic:
                return "Wide screen with blurred background"
            }
        }
    }

    /// Available aspect ratios
    public enum AspectRatio: String, Codable, Sendable, CaseIterable {
        case landscape16_9 = "16:9"
        case portrait9_16 = "9:16"
        case square1_1 = "1:1"
        case landscape4_3 = "4:3"

        /// Display name for the aspect ratio
        public var displayName: String {
            rawValue
        }

        /// Width for a given height (1080 base)
        public func width(for height: Int = 1080) -> Int {
            switch self {
            case .landscape16_9:
                return 1920
            case .portrait9_16:
                return 607
            case .square1_1:
                return height
            case .landscape4_3:
                return 1440
            }
        }

        /// Height for a given width (1920 base)
        public func height(for width: Int = 1920) -> Int {
            switch self {
            case .landscape16_9:
                return 1080
            case .portrait9_16:
                return 3402
            case .square1_1:
                return width
            case .landscape4_3:
                return 1440
            }
        }
    }

    /// Available background types
    public enum BackgroundType: String, Codable, Sendable, CaseIterable {
        case solid = "solid"
        case image = "image"
        case blur = "blur"

        /// Display name for the background type
        public var displayName: String {
            switch self {
            case .solid:
                return "Solid Color"
            case .image:
                return "Image"
            case .blur:
                return "Blurred Screen"
            }
        }
    }

    /// Image fit modes for background images
    public enum ImageFitMode: String, Codable, Sendable, CaseIterable {
        case fit = "fit"    // Contain: entire image visible, may have letterboxing
        case fill = "fill"  // Cover: fill entire canvas, may crop image

        /// Display name for the fit mode
        public var displayName: String {
            switch self {
            case .fit:
                return "Fit (Contain)"
            case .fill:
                return "Fill (Cover)"
            }
        }

        /// Description of the fit mode
        public var description: String {
            switch self {
            case .fit:
                return "Show entire image with letterboxing if needed"
            case .fill:
                return "Fill canvas, cropping image if needed"
            }
        }
    }

    /// Layout configuration errors
    public enum LayoutError: Error, LocalizedError, Sendable, Equatable {
        case invalidAspectRatio(String)
        case invalidLayoutPreset(String)
        case invalidCameraPosition(String)
        case missingCameraTrack
        case invalidBackgroundValue(String)

        public var errorDescription: String? {
            switch self {
            case .invalidAspectRatio(let aspect):
                return "Invalid aspect ratio: \(aspect)"
            case .invalidLayoutPreset(let preset):
                return "Invalid layout preset: \(preset)"
            case .invalidCameraPosition(let reason):
                return "Invalid camera position: \(reason)"
            case .missingCameraTrack:
                return "Camera track is required for this layout"
            case .invalidBackgroundValue(let value):
                return "Invalid background value: \(value)"
            }
        }
    }
}
