//
//  TelemetryParserTypes.swift
//  EngineKit
//
//  Extracted from TelemetryParser.swift — types, configuration, and errors
//

import Foundation
import CoreGraphics

extension TelemetryParser {
    /// Configuration for telemetry parsing
    public struct Configuration {
        /// Time window size for grouping clicks (seconds)
        /// Default: 2.0 seconds - clicks within this window are grouped together
        public let timeWindowSize: TimeInterval

        /// Minimum clicks to consider a window "important"
        /// Default: 2 clicks - windows with fewer clicks are not considered for zoom
        public let minClicksPerWindow: Int

        /// Maximum time between clicks in a cluster (seconds)
        /// Default: 1.0 second - clicks closer than this are part of the same cluster
        public let maxClickInterval: TimeInterval

        /// Minimum cursor movement distance to consider a click "important" (pixels)
        /// Default: 50 pixels - clicks with less movement are filtered out
        public let minMovementDistance: Double

        /// Whether to include left clicks
        public let includeLeftClicks: Bool

        /// Whether to include right clicks
        public let includeRightClicks: Bool

        /// Whether to include middle/other clicks
        public let includeOtherClicks: Bool

        public init(
            timeWindowSize: TimeInterval = 2.0,
            minClicksPerWindow: Int = 2,
            maxClickInterval: TimeInterval = 1.0,
            minMovementDistance: Double = 50.0,
            includeLeftClicks: Bool = true,
            includeRightClicks: Bool = false,
            includeOtherClicks: Bool = false
        ) {
            self.timeWindowSize = timeWindowSize
            self.minClicksPerWindow = minClicksPerWindow
            self.maxClickInterval = maxClickInterval
            self.minMovementDistance = minMovementDistance
            self.includeLeftClicks = includeLeftClicks
            self.includeRightClicks = includeRightClicks
            self.includeOtherClicks = includeOtherClicks
        }

        /// Default configuration for tutorial/demo recordings
        public static func `default`() -> Configuration {
            return Configuration()
        }

        /// Aggressive configuration - detects more zoom points
        public static func aggressive() -> Configuration {
            return Configuration(
                timeWindowSize: 3.0,
                minClicksPerWindow: 1,
                maxClickInterval: 1.5,
                minMovementDistance: 30.0,
                includeLeftClicks: true,
                includeRightClicks: true,
                includeOtherClicks: false
            )
        }

        /// Conservative configuration - detects fewer zoom points
        public static func conservative() -> Configuration {
            return Configuration(
                timeWindowSize: 1.5,
                minClicksPerWindow: 3,
                maxClickInterval: 0.75,
                minMovementDistance: 80.0,
                includeLeftClicks: true,
                includeRightClicks: false,
                includeOtherClicks: false
            )
        }
    }

    /// A detected important click with metadata
    public struct ImportantClick: Identifiable, Codable {
        /// Unique identifier
        public let id: UUID
        /// Timestamp in seconds from recording start
        public let timestamp: TimeInterval
        /// Cursor X position
        public let x: Int
        /// Cursor Y position
        public let y: Int
        /// Mouse button (0=left, 1=right, 2=middle)
        public let button: Int
        /// Time since previous click (seconds)
        public let timeSincePreviousClick: TimeInterval
        /// Distance from previous click (pixels)
        public let distanceFromPreviousClick: Double
        /// Window ID this click belongs to
        public let windowId: UUID
        /// Display ID (for multi-monitor setups)
        public let displayID: String?

        public init(
            id: UUID = UUID(),
            timestamp: TimeInterval,
            x: Int,
            y: Int,
            button: Int,
            timeSincePreviousClick: TimeInterval,
            distanceFromPreviousClick: Double,
            windowId: UUID,
            displayID: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.x = x
            self.y = y
            self.button = button
            self.timeSincePreviousClick = timeSincePreviousClick
            self.distanceFromPreviousClick = distanceFromPreviousClick
            self.windowId = windowId
            self.displayID = displayID
        }
    }

    /// A temporal window containing grouped clicks
    public struct ClickWindow: Identifiable, Codable {
        /// Unique identifier
        public let id: UUID
        /// Window start time (seconds from recording start)
        public let startTime: TimeInterval
        /// Window end time (seconds from recording start)
        public let endTime: TimeInterval
        /// Duration of the window (seconds)
        public let duration: TimeInterval
        /// Important clicks in this window
        public let clicks: [ImportantClick]
        /// Center point of all clicks in this window (average X, Y)
        public let centerPoint: CGPoint
        /// Bounding box of all clicks in this window
        public let boundingBox: BoundingBox
        /// Click count in this window
        public let clickCount: Int
        /// Importance score (higher = more important)
        public let importanceScore: Double

        public init(
            id: UUID = UUID(),
            startTime: TimeInterval,
            endTime: TimeInterval,
            clicks: [ImportantClick],
            centerPoint: CGPoint,
            boundingBox: BoundingBox,
            importanceScore: Double
        ) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.duration = endTime - startTime
            self.clicks = clicks
            self.centerPoint = centerPoint
            self.boundingBox = boundingBox
            self.clickCount = clicks.count
            self.importanceScore = importanceScore
        }
    }

    /// Bounding box for a set of points
    public struct BoundingBox: Codable {
        /// Minimum X coordinate
        public let minX: Int
        /// Maximum X coordinate
        public let maxX: Int
        /// Minimum Y coordinate
        public let minY: Int
        /// Maximum Y coordinate
        public let maxY: Int
        /// Width of the bounding box
        public let width: Int
        /// Height of the bounding box
        public let height: Int

        public init(minX: Int, maxX: Int, minY: Int, maxY: Int) {
            self.minX = minX
            self.maxX = maxX
            self.minY = minY
            self.maxY = maxY
            self.width = maxX - minX
            self.height = maxY - minY
        }

        /// Center point of the bounding box
        public var center: CGPoint {
            return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }
    }

    /// Parsing result with detected important clicks and windows
    public struct ParseResult {
        /// All detected important clicks
        public let importantClicks: [ImportantClick]
        /// Temporal windows with grouped clicks
        public let windows: [ClickWindow]
        /// Statistics about the parsing
        public let stats: ParseStats

        public init(
            importantClicks: [ImportantClick],
            windows: [ClickWindow],
            stats: ParseStats
        ) {
            self.importantClicks = importantClicks
            self.windows = windows
            self.stats = stats
        }
    }

    /// Statistics about telemetry parsing
    public struct ParseStats {
        /// Total events processed
        public let totalEvents: Int
        /// Total clicks (down events) processed
        public let totalClicks: Int
        /// Important clicks detected
        public let importantClickCount: Int
        /// Windows created
        public let windowCount: Int
        /// Clicks per second average
        public let clicksPerSecond: Double
        /// Time range covered by telemetry
        public let timeRange: ClosedRange<TimeInterval>

        public init(
            totalEvents: Int,
            totalClicks: Int,
            importantClickCount: Int,
            windowCount: Int,
            clicksPerSecond: Double,
            timeRange: ClosedRange<TimeInterval>
        ) {
            self.totalEvents = totalEvents
            self.totalClicks = totalClicks
            self.importantClickCount = importantClickCount
            self.windowCount = windowCount
            self.clicksPerSecond = clicksPerSecond
            self.timeRange = timeRange
        }
    }

    /// Parser errors
    public enum ParserError: LocalizedError {
        case fileNotFound(URL)
        case invalidFileFormat
        case emptyFile
        case readFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "Telemetry file not found: \(url.path)"
            case .invalidFileFormat:
                return "Invalid telemetry file format"
            case .emptyFile:
                return "Telemetry file is empty"
            case .readFailed(let error):
                return "Failed to read telemetry file: \(error.localizedDescription)"
            }
        }
    }
}
