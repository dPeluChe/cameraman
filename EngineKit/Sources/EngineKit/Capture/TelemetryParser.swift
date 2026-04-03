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
            assertionFailure("createWindow called with empty clicks — caller should guard")
            return ClickWindow(
                id: windowId,
                startTime: startTime,
                endTime: startTime,
                clicks: [],
                centerPoint: .zero,
                boundingBox: BoundingBox(minX: 0, maxX: 0, minY: 0, maxY: 0),
                importanceScore: 0
            )
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
