//
//  CaptionsManagerTypes.swift
//  EngineKit
//
//  Extracted from CaptionsManager.swift — types, styles, and errors
//

import Foundation

extension CaptionsManager {
    /// Caption entry with timing and text
    public struct CaptionEntry: Codable, Equatable, Identifiable {
        public let id: Int
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String

        public init(id: Int, start: TimeInterval, end: TimeInterval, text: String) {
            self.id = id
            self.start = start
            self.end = end
            self.text = text
        }
    }

    /// Caption style configuration
    public struct CaptionStyle: Equatable, Sendable {
        /// Font family
        public let fontFamily: String
        /// Font size (relative to video height)
        public let fontSize: Double
        /// Text color (hex)
        public let textColor: String
        /// Background color (hex)
        public let backgroundColor: String
        /// Background opacity (0.0 to 1.0)
        public let backgroundOpacity: Double
        /// Position on screen (0.0 = bottom, 1.0 = top)
        public let verticalPosition: Double
        /// Horizontal alignment (0.0 = left, 0.5 = center, 1.0 = right)
        public let horizontalAlignment: Double
        /// Maximum line width (0.0 to 1.0, relative to video width)
        public let maxLineWidth: Double
        /// Number of lines to display
        public let maxLines: Int
        /// Text shadow enabled
        public let shadow: Bool

        public init(
            fontFamily: String = "Helvetica",
            fontSize: Double = 0.06, // 6% of video height
            textColor: String = "#FFFFFF",
            backgroundColor: String = "#000000",
            backgroundOpacity: Double = 0.7,
            verticalPosition: Double = 0.1, // 10% from bottom
            horizontalAlignment: Double = 0.5, // Centered
            maxLineWidth: Double = 0.8, // 80% of video width
            maxLines: Int = 2,
            shadow: Bool = true
        ) {
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.backgroundOpacity = backgroundOpacity
            self.verticalPosition = verticalPosition
            self.horizontalAlignment = horizontalAlignment
            self.maxLineWidth = maxLineWidth
            self.maxLines = maxLines
            self.shadow = shadow
        }

        /// Default caption style
        public static let `default` = CaptionStyle()

        /// Large text style (accessibility)
        public static let large = CaptionStyle(
            fontSize: 0.08,
            backgroundOpacity: 0.8,
            maxLines: 3
        )

        /// Minimal style (no background)
        public static let minimal = CaptionStyle(
            fontSize: 0.05,
            backgroundOpacity: 0.0,
            shadow: true
        )
    }

    /// Caption format
    public enum CaptionFormat: String {
        case srt
        case vtt
    }

    /// CaptionsManager errors
    public enum CaptionsError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case parseError(String)
        case emptyFile

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Caption file not found: \(path)"
            case .invalidFormat(let reason):
                return "Invalid caption format: \(reason)"
            case .parseError(let reason):
                return "Failed to parse captions: \(reason)"
            case .emptyFile:
                return "Caption file is empty"
            }
        }
    }
}
