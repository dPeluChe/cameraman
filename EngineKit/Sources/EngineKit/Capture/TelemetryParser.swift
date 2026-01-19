//
//  TelemetryParser.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// TelemetryParser analyzes telemetry data to detect "important" clicks and group events into temporal windows
/// for auto-zoom functionality (Épica I, Task 1)
public actor TelemetryParser {
    // MARK: - Types

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

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Parse telemetry file and detect important clicks and temporal windows
    /// - Parameter telemetryFile: Path to cursor.jsonl file
    /// - Parameter config: Parsing configuration
    /// - Returns: ParseResult with important clicks and windows
    public func parse(
        telemetryFile: URL,
        config: Configuration = .default()
    ) async throws -> ParseResult {
        // Load telemetry events from file
        let events = try await loadTelemetryEvents(from: telemetryFile)

        // Filter click events (down events only)
        let clickEvents = events.filter { $0.type == .down }
            .filter { event in
                // Filter by button type based on configuration
                guard let button = event.button else { return false }
                switch button {
                case 0: return config.includeLeftClicks
                case 1: return config.includeRightClicks
                default: return config.includeOtherClicks
                }
            }

        // Detect important clicks
        let importantClicks = detectImportantClicks(
            from: clickEvents,
            config: config
        )

        // Group clicks into temporal windows
        let windows = groupClicksIntoWindows(
            clicks: importantClicks,
            config: config
        )

        // Calculate statistics
        let stats = calculateStats(
            totalEvents: events.count,
            totalClicks: clickEvents.count,
            importantClicks: importantClicks,
            windows: windows
        )

        return ParseResult(
            importantClicks: importantClicks,
            windows: windows,
            stats: stats
        )
    }

    /// Parse telemetry events directly (without loading from file)
    /// - Parameter events: Array of telemetry events
    /// - Parameter config: Parsing configuration
    /// - Returns: ParseResult with important clicks and windows
    public func parseEvents(
        _ events: [TelemetryRecorder.Event],
        config: Configuration = .default()
    ) async throws -> ParseResult {
        // Filter click events (down events only)
        let clickEvents = events.filter { $0.type == .down }
            .filter { event in
                // Filter by button type based on configuration
                guard let button = event.button else { return false }
                switch button {
                case 0: return config.includeLeftClicks
                case 1: return config.includeRightClicks
                default: return config.includeOtherClicks
                }
            }

        // Detect important clicks
        let importantClicks = detectImportantClicks(
            from: clickEvents,
            config: config
        )

        // Group clicks into temporal windows
        let windows = groupClicksIntoWindows(
            clicks: importantClicks,
            config: config
        )

        // Calculate statistics
        let stats = calculateStats(
            totalEvents: events.count,
            totalClicks: clickEvents.count,
            importantClicks: importantClicks,
            windows: windows
        )

        return ParseResult(
            importantClicks: importantClicks,
            windows: windows,
            stats: stats
        )
    }

    // MARK: - Private Methods

    /// Load telemetry events from JSONL file
    private func loadTelemetryEvents(from url: URL) async throws -> [TelemetryRecorder.Event] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParserError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ParserError.emptyFile
        }

        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        var events: [TelemetryRecorder.Event] = []

        for line in lines where !line.isEmpty {
            if let lineData = line.data(using: .utf8) {
                do {
                    let event = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: lineData)
                    events.append(event)
                } catch {
                    // Skip invalid lines
                    continue
                }
            }
        }

        return events
    }

    /// Detect important clicks from click events
    private func detectImportantClicks(
        from clickEvents: [TelemetryRecorder.Event],
        config: Configuration
    ) -> [ImportantClick] {
        guard !clickEvents.isEmpty else { return [] }

        var importantClicks: [ImportantClick] = []
        var windowId = UUID()
        var previousClick: TelemetryRecorder.Event?
        var previousPosition: CGPoint?

        for click in clickEvents {
            let currentPosition = CGPoint(x: click.x, y: click.y)

            // Calculate time since previous click
            let timeSincePreviousClick: TimeInterval
            if let prev = previousClick {
                timeSincePreviousClick = click.t - prev.t
            } else {
                timeSincePreviousClick = 0
            }

            // Calculate distance from previous click
            let distanceFromPreviousClick: Double
            if let prevPos = previousPosition {
                let deltaX = currentPosition.x - prevPos.x
                let deltaY = currentPosition.y - prevPos.y
                distanceFromPreviousClick = sqrt(deltaX * deltaX + deltaY * deltaY)
            } else {
                distanceFromPreviousClick = 0
            }

            // Check if this click starts a new window
            if timeSincePreviousClick > config.maxClickInterval {
                windowId = UUID()
            }

            // Filter clicks that don't meet minimum movement distance
            // (except for the first click in a window, which is always included)
            if distanceFromPreviousClick >= config.minMovementDistance || previousClick == nil {
                let importantClick = ImportantClick(
                    timestamp: click.t,
                    x: click.x,
                    y: click.y,
                    button: click.button ?? 0,
                    timeSincePreviousClick: timeSincePreviousClick,
                    distanceFromPreviousClick: distanceFromPreviousClick,
                    windowId: windowId,
                    displayID: click.displayID
                )

                importantClicks.append(importantClick)
            }

            previousClick = click
            previousPosition = currentPosition
        }

        return importantClicks
    }

    /// Group important clicks into temporal windows
    private func groupClicksIntoWindows(
        clicks: [ImportantClick],
        config: Configuration
    ) -> [ClickWindow] {
        guard !clicks.isEmpty else { return [] }

        var windows: [ClickWindow] = []
        var currentWindowClicks: [ImportantClick] = []
        var windowStartTime: TimeInterval?
        let windowIdGenerator = UUID()

        for click in clicks {
            // Start new window if needed
            if windowStartTime == nil {
                windowStartTime = click.timestamp
                currentWindowClicks.append(click)
            } else {
                let timeInWindow = click.timestamp - windowStartTime!

                // Check if click is within the time window
                if timeInWindow <= config.timeWindowSize {
                    currentWindowClicks.append(click)
                } else {
                    // Finalize current window if it meets minimum click threshold
                    if currentWindowClicks.count >= config.minClicksPerWindow {
                        let window = createWindow(
                            from: currentWindowClicks,
                            startTime: windowStartTime!,
                            windowId: windowIdGenerator
                        )
                        windows.append(window)
                    }

                    // Start new window
                    windowStartTime = click.timestamp
                    currentWindowClicks = [click]
                }
            }
        }

        // Don't forget the last window
        if let start = windowStartTime, currentWindowClicks.count >= config.minClicksPerWindow {
            let window = createWindow(
                from: currentWindowClicks,
                startTime: start,
                windowId: windowIdGenerator
            )
            windows.append(window)
        }

        return windows
    }

    /// Create a ClickWindow from a list of clicks
    private func createWindow(
        from clicks: [ImportantClick],
        startTime: TimeInterval,
        windowId: UUID
    ) -> ClickWindow {
        guard !clicks.isEmpty else {
            fatalError("Cannot create window from empty clicks array")
        }

        let endTime = clicks.map { $0.timestamp }.max() ?? startTime

        // Calculate center point (average of all click positions)
        let totalX = clicks.reduce(0) { $0 + $1.x }
        let totalY = clicks.reduce(0) { $0 + $1.y }
        let centerX = Double(totalX) / Double(clicks.count)
        let centerY = Double(totalY) / Double(clicks.count)
        let centerPoint = CGPoint(x: centerX, y: centerY)

        // Calculate bounding box
        let minX = clicks.map { $0.x }.min() ?? 0
        let maxX = clicks.map { $0.x }.max() ?? 0
        let minY = clicks.map { $0.y }.min() ?? 0
        let maxY = clicks.map { $0.y }.max() ?? 0
        let boundingBox = BoundingBox(minX: minX, maxX: maxX, minY: minY, maxY: maxY)

        // Calculate importance score
        // Higher score = more important (more clicks, shorter duration, tighter cluster)
        let duration = endTime - startTime
        let clickDensity = Double(clicks.count) / max(duration, 0.1)
        let clusterTightness = boundingBox.width > 0 && boundingBox.height > 0
            ? Double(clicks.count) / Double(boundingBox.width * boundingBox.height) * 10000
            : 0
        let importanceScore = clickDensity * 10 + clusterTightness

        return ClickWindow(
            id: windowId,
            startTime: startTime,
            endTime: endTime,
            clicks: clicks,
            centerPoint: centerPoint,
            boundingBox: boundingBox,
            importanceScore: importanceScore
        )
    }

    /// Calculate parsing statistics
    private func calculateStats(
        totalEvents: Int,
        totalClicks: Int,
        importantClicks: [ImportantClick],
        windows: [ClickWindow]
    ) -> ParseStats {
        let timeRange: ClosedRange<TimeInterval>
        if let minTime = importantClicks.map({ $0.timestamp }).min(),
           let maxTime = importantClicks.map({ $0.timestamp }).max() {
            timeRange = minTime...maxTime
        } else {
            timeRange = 0...0
        }

        let duration = timeRange.upperBound - timeRange.lowerBound
        let clicksPerSecond = duration > 0 ? Double(importantClicks.count) / duration : 0

        return ParseStats(
            totalEvents: totalEvents,
            totalClicks: totalClicks,
            importantClickCount: importantClicks.count,
            windowCount: windows.count,
            clicksPerSecond: clicksPerSecond,
            timeRange: timeRange
        )
    }
}
