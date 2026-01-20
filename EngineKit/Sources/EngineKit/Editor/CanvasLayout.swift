//
//  CanvasLayout.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import CoreGraphics

/// Canvas layout manager for video composition
/// Supports PiP (Picture-in-Picture) and side-by-side layouts
public actor CanvasLayout {
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

    /// Default layouts for common presets
    public static func defaultLayout(for preset: LayoutPreset) -> Project.Canvas.Layout {
        switch preset {
        case .pip:
            return Project.Canvas.Layout(
                type: preset.rawValue,
                camera: Project.Canvas.Layout.CameraPosition(
                    x: 0.74,
                    y: 0.72,
                    w: 0.22,
                    h: 0.22,
                    cornerRadius: 18
                )
            )

        case .sideBySide:
            return Project.Canvas.Layout(
                type: preset.rawValue,
                camera: Project.Canvas.Layout.CameraPosition(
                    x: 0.51,
                    y: 0.25,
                    w: 0.47,
                    h: 0.5,
                    cornerRadius: 12
                )
            )

        case .fullscreen:
            return Project.Canvas.Layout(
                type: preset.rawValue,
                camera: nil
            )

        case .cinematic:
            return Project.Canvas.Layout(
                type: preset.rawValue,
                camera: Project.Canvas.Layout.CameraPosition(
                    x: 0.5,
                    y: 0.5,
                    w: 0.9,
                    h: 0.6,
                    cornerRadius: 24
                )
            )
        }
    }

    /// Default backgrounds for common types
    public static func defaultBackground(
        for type: BackgroundType,
        fitMode: ImageFitMode = .fill
    ) -> Project.Canvas.Background {
        switch type {
        case .solid:
            return Project.Canvas.Background(
                type: type.rawValue,
                value: "#0B0B0D",
                fitMode: nil
            )

        case .image:
            return Project.Canvas.Background(
                type: type.rawValue,
                value: "", // Empty path - user must provide image
                fitMode: fitMode.rawValue
            )

        case .blur:
            return Project.Canvas.Background(
                type: type.rawValue,
                value: "10", // Blur radius
                fitMode: nil
            )
        }
    }

    /// Calculate camera frame for a given layout and canvas size
    public static func calculateCameraFrame(
        layout: Project.Canvas.Layout,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> CGRect? {
        guard let camera = layout.camera else {
            return nil
        }

        let x = CGFloat(camera.x) * CGFloat(canvasWidth)
        let y = CGFloat(camera.y) * CGFloat(canvasHeight)
        let w = CGFloat(camera.w) * CGFloat(canvasWidth)
        let h = CGFloat(camera.h) * CGFloat(canvasHeight)

        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Calculate screen frame for a given layout and canvas size
    public static func calculateScreenFrame(
        layout: Project.Canvas.Layout,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> CGRect {
        switch layout.type {
        case "pip", "cinematic":
            // Screen fills the entire canvas
            return CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))

        case "side-by-side":
            // Screen takes left half (with some padding)
            let padding: CGFloat = 10
            let screenWidth = CGFloat(canvasWidth) * 0.49
            return CGRect(
                x: padding,
                y: padding,
                width: screenWidth,
                height: CGFloat(canvasHeight) - 2 * padding
            )

        case "fullscreen":
            // Screen fills the entire canvas (no camera overlay)
            return CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))

        default:
            // Default to full screen
            return CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight))
        }
    }

    /// Validate layout configuration
    public static func validateLayout(_ layout: Project.Canvas.Layout, hasCamera: Bool) throws {
        // Validate layout type
        guard LayoutPreset(rawValue: layout.type) != nil else {
            throw LayoutError.invalidLayoutPreset(layout.type)
        }

        // Validate camera position if present
        if let camera = layout.camera {
            // Check if camera position is within valid bounds (0-1)
            guard camera.x >= 0 && camera.x <= 1 else {
                throw LayoutError.invalidCameraPosition("x must be between 0 and 1, got \(camera.x)")
            }
            guard camera.y >= 0 && camera.y <= 1 else {
                throw LayoutError.invalidCameraPosition("y must be between 0 and 1, got \(camera.y)")
            }
            guard camera.w > 0 && camera.w <= 1 else {
                throw LayoutError.invalidCameraPosition("w must be between 0 and 1, got \(camera.w)")
            }
            guard camera.h > 0 && camera.h <= 1 else {
                throw LayoutError.invalidCameraPosition("h must be between 0 and 1, got \(camera.h)")
            }
            guard camera.cornerRadius >= 0 else {
                throw LayoutError.invalidCameraPosition("cornerRadius must be non-negative, got \(camera.cornerRadius)")
            }

            // Check if camera frame stays within bounds
            let maxX = camera.x + camera.w
            let maxY = camera.y + camera.h
            guard maxX <= 1.0 else {
                throw LayoutError.invalidCameraPosition("camera frame exceeds canvas width (x + w = \(maxX))")
            }
            guard maxY <= 1.0 else {
                throw LayoutError.invalidCameraPosition("camera frame exceeds canvas height (y + h = \(maxY))")
            }
        }

        // Validate that layouts requiring camera have camera position
        if layout.type == LayoutPreset.pip.rawValue ||
           layout.type == LayoutPreset.sideBySide.rawValue ||
           layout.type == LayoutPreset.cinematic.rawValue {
            if layout.camera == nil && hasCamera {
                throw LayoutError.invalidCameraPosition("layout '\(layout.type)' requires camera position")
            }
        }
    }

    /// Validate background configuration
    public static func validateBackground(_ background: Project.Canvas.Background) throws {
        guard BackgroundType(rawValue: background.type) != nil else {
            throw LayoutError.invalidBackgroundValue(background.type)
        }

        switch background.type {
        case "solid":
            // Validate hex color format (#RRGGBB or #RRGGBBAA)
            let hexPattern = #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#
            let isValid = background.value.range(of: hexPattern, options: .regularExpression) != nil
            if !isValid {
                throw LayoutError.invalidBackgroundValue("Invalid hex color format: \(background.value). Expected #RRGGBB or #RRGGBBAA")
            }

        case "image":
            // Validate fit mode if provided
            if let fitMode = background.fitMode {
                guard ImageFitMode(rawValue: fitMode) != nil else {
                    throw LayoutError.invalidBackgroundValue("Invalid fit mode: \(fitMode). Expected 'fit' or 'fill'")
                }
            }
            // Image path can be empty (user hasn't selected one yet)

        case "blur":
            // Validate blur radius is a valid number
            if let blurRadius = Double(background.value) {
                if blurRadius < 0 || blurRadius > 100 {
                    throw LayoutError.invalidBackgroundValue("Blur radius must be between 0 and 100, got \(blurRadius)")
                }
            } else {
                throw LayoutError.invalidBackgroundValue("Invalid blur radius: \(background.value)")
            }

        default:
            throw LayoutError.invalidBackgroundValue("Unknown background type: \(background.type)")
        }
    }

    /// Validate format configuration
    public static func validateFormat(_ format: Project.Canvas.Format) throws {
        guard AspectRatio(rawValue: format.aspect) != nil else {
            throw LayoutError.invalidAspectRatio(format.aspect)
        }

        guard format.w > 0 else {
            throw LayoutError.invalidAspectRatio("Width must be positive, got \(format.w)")
        }

        guard format.h > 0 else {
            throw LayoutError.invalidAspectRatio("Height must be positive, got \(format.h)")
        }

        // Validate aspect ratio matches dimensions
        let expectedRatio = Double(format.w) / Double(format.h)
        let actualRatio: Double

        switch format.aspect {
        case "16:9":
            actualRatio = 16.0 / 9.0
        case "9:16":
            actualRatio = 9.0 / 16.0
        case "1:1":
            actualRatio = 1.0
        case "4:3":
            actualRatio = 4.0 / 3.0
        default:
            actualRatio = expectedRatio
        }

        let tolerance = 0.01
        if abs(expectedRatio - actualRatio) > tolerance {
            throw LayoutError.invalidAspectRatio("Dimensions \(format.w)x\(format.h) don't match aspect ratio \(format.aspect)")
        }
    }

    /// Create a format for a given aspect ratio
    public static func createFormat(for aspectRatio: AspectRatio, baseWidth: Int = 1920) -> Project.Canvas.Format {
        let width: Int
        let height: Int

        switch aspectRatio {
        case .landscape16_9:
            width = baseWidth
            height = aspectRatio.height(for: baseWidth)

        case .portrait9_16:
            width = aspectRatio.width(for: 1080)
            height = 3402

        case .square1_1:
            width = 1080
            height = 1080

        case .landscape4_3:
            width = 1440
            height = 1080
        }

        return Project.Canvas.Format(
            aspect: aspectRatio.rawValue,
            w: width,
            h: height
        )
    }

    /// Create a solid color background
    public static func createSolidBackground(hexColor: String) -> Project.Canvas.Background {
        return Project.Canvas.Background(
            type: BackgroundType.solid.rawValue,
            value: hexColor,
            fitMode: nil
        )
    }

    /// Create an image background with specified fit mode
    public static func createImageBackground(
        imagePath: String,
        fitMode: ImageFitMode = .fill
    ) -> Project.Canvas.Background {
        return Project.Canvas.Background(
            type: BackgroundType.image.rawValue,
            value: imagePath,
            fitMode: fitMode.rawValue
        )
    }

    /// Create a blurred screen background
    public static func createBlurBackground(radius: Int = 10) -> Project.Canvas.Background {
        return Project.Canvas.Background(
            type: BackgroundType.blur.rawValue,
            value: String(radius),
            fitMode: nil
        )
    }

    /// Calculate image frame for background with fit/fill mode
    /// Returns the frame where the background image should be drawn
    public static func calculateImageFrame(
        imageSize: CGSize,
        canvasSize: CGSize,
        fitMode: ImageFitMode
    ) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let canvasAspect = canvasSize.width / canvasSize.height

        var frame: CGRect

        switch fitMode {
        case .fit:
            // Contain: fit entire image within canvas
            if imageAspect > canvasAspect {
                // Image is wider than canvas - fit to width
                let width = canvasSize.width
                let height = width / imageAspect
                let x = CGFloat(0)
                let y = (canvasSize.height - height) / 2
                frame = CGRect(x: x, y: y, width: width, height: height)
            } else {
                // Image is taller than canvas - fit to height
                let height = canvasSize.height
                let width = height * imageAspect
                let x = (canvasSize.width - width) / 2
                let y = CGFloat(0)
                frame = CGRect(x: x, y: y, width: width, height: height)
            }

        case .fill:
            // Cover: fill entire canvas with image (may crop)
            if imageAspect > canvasAspect {
                // Image is wider than canvas - fit to height
                let height = canvasSize.height
                let width = height * imageAspect
                let x = (canvasSize.width - width) / 2
                let y = CGFloat(0)
                frame = CGRect(x: x, y: y, width: width, height: height)
            } else {
                // Image is taller than canvas - fit to width
                let width = canvasSize.width
                let height = width / imageAspect
                let x = CGFloat(0)
                let y = (canvasSize.height - height) / 2
                frame = CGRect(x: x, y: y, width: width, height: height)
            }
        }

        return frame
    }

    /// Parse hex color to RGB components
    /// Supports #RRGGBB and #RRGGBBAA formats
    public static func parseHexColor(_ hex: String) -> (r: Int, g: Int, b: Int, a: Int)? {
        // Remove # prefix if present
        let cleanHex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        // Validate hex format
        let hexPattern = #"^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#
        guard cleanHex.range(of: hexPattern, options: .regularExpression) != nil else {
            return nil
        }

        // Parse components
        var r: Int = 0
        var g: Int = 0
        var b: Int = 0
        var a: Int = 255

        let index = cleanHex.startIndex

        r = Int(cleanHex[index..<cleanHex.index(index, offsetBy: 2)], radix: 16) ?? 0
        g = Int(cleanHex[cleanHex.index(index, offsetBy: 2)..<cleanHex.index(index, offsetBy: 4)], radix: 16) ?? 0
        b = Int(cleanHex[cleanHex.index(index, offsetBy: 4)..<cleanHex.index(index, offsetBy: 6)], radix: 16) ?? 0

        if cleanHex.count == 8 {
            a = Int(cleanHex[cleanHex.index(index, offsetBy: 6)..<cleanHex.index(index, offsetBy: 8)], radix: 16) ?? 255
        }

        return (r, g, b, a)
    }

    /// Get recommended layout presets for a given aspect ratio
    public static func recommendedLayouts(for aspectRatio: AspectRatio) -> [LayoutPreset] {
        switch aspectRatio {
        case .landscape16_9:
            return [.pip, .sideBySide, .fullscreen, .cinematic]

        case .portrait9_16:
            return [.pip, .fullscreen] // Side-by-side doesn't work well in portrait

        case .square1_1:
            return [.pip, .sideBySide, .fullscreen]

        case .landscape4_3:
            return [.pip, .sideBySide, .fullscreen]
        }
    }

    /// Check if a layout preset is compatible with an aspect ratio
    public static func isLayoutCompatible(
        layout: LayoutPreset,
        aspectRatio: AspectRatio
    ) -> Bool {
        switch (layout, aspectRatio) {
        case (.sideBySide, .portrait9_16):
            return false // Side-by-side doesn't work well in portrait

        default:
            return true
        }
    }

    /// Adjust camera position for different aspect ratios
    /// This helps maintain visual consistency when switching formats
    public static func adjustCameraPosition(
        _ camera: Project.Canvas.Layout.CameraPosition,
        from sourceRatio: AspectRatio,
        to targetRatio: AspectRatio
    ) -> Project.Canvas.Layout.CameraPosition {
        // For most cases, keep relative position the same
        // But may need adjustments for extreme aspect ratio changes

        // If going from landscape to portrait, move camera to bottom center
        if sourceRatio == .landscape16_9 && targetRatio == .portrait9_16 {
            return Project.Canvas.Layout.CameraPosition(
                x: 0.5 - (camera.w / 2), // Center horizontally
                y: 0.75, // Move to bottom
                w: min(camera.w, 0.6), // Limit width in portrait
                h: camera.h,
                cornerRadius: camera.cornerRadius
            )
        }

        // If going from portrait to landscape, restore to corner
        if sourceRatio == .portrait9_16 && targetRatio == .landscape16_9 {
            return Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: camera.cornerRadius
            )
        }

        // Default: keep original position
        return camera
    }
}

