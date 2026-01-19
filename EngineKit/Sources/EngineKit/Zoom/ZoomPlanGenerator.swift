//
//  ZoomPlanGenerator.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// ZoomPlanGenerator generates zoom keyframe plans from telemetry parser results
/// Provides smooth camera movements with easing functions and configurable limits (Épica I, Task 2)
public actor ZoomPlanGenerator {
    // MARK: - Types

    /// Configuration for zoom plan generation
    public struct Configuration: Equatable {
        /// Minimum zoom level (1.0 = no zoom)
        /// Default: 1.0 - no zoom out beyond original
        public let minZoomLevel: Double

        /// Maximum zoom level (2.0 = 2x zoom, 3.0 = 3x zoom)
        /// Default: 2.5 - reasonable zoom that doesn't disorient viewers
        public let maxZoomLevel: Double

        /// Default zoom level when not actively zooming
        /// Default: 1.0 - no zoom
        public let defaultZoomLevel: Double

        /// Duration of zoom-in animation (seconds)
        /// Default: 0.5 seconds - smooth but responsive
        public let zoomInDuration: TimeInterval

        /// Duration of zoom-out animation (seconds)
        /// Default: 0.7 seconds - slightly slower for smoother return
        public let zoomOutDuration: TimeInterval

        /// Duration to hold zoom before releasing (seconds)
        /// Default: 1.0 seconds - gives viewers time to see zoomed content
        public let holdDuration: TimeInterval

        /// Padding around click bounding box (percentage, 0.0-1.0)
        /// Default: 0.15 (15% padding) - ensures cursor/element isn't at edge
        public let boundingBoxPadding: Double

        /// Easing function for zoom animations
        /// Default: easeInOut - smooth acceleration and deceleration
        public let easingFunction: EasingFunction

        /// Maximum number of zoom events per minute (prevents excessive zooming)
        /// Default: 6 zooms per minute - avoids disorienting viewers
        public let maxZoomsPerMinute: Int

        /// Minimum time between zoom events (seconds)
        /// Default: 3.0 seconds - prevents rapid zoom in/out
        public let minTimeBetweenZooms: TimeInterval

        /// Whether to enable zoom (can be toggled per section)
        /// Default: true
        public let zoomEnabled: Bool

        public init(
            minZoomLevel: Double = 1.0,
            maxZoomLevel: Double = 2.5,
            defaultZoomLevel: Double = 1.0,
            zoomInDuration: TimeInterval = 0.5,
            zoomOutDuration: TimeInterval = 0.7,
            holdDuration: TimeInterval = 1.0,
            boundingBoxPadding: Double = 0.15,
            easingFunction: EasingFunction = .easeInOut,
            maxZoomsPerMinute: Int = 6,
            minTimeBetweenZooms: TimeInterval = 3.0,
            zoomEnabled: Bool = true
        ) {
            self.minZoomLevel = minZoomLevel
            self.maxZoomLevel = maxZoomLevel
            self.defaultZoomLevel = defaultZoomLevel
            self.zoomInDuration = zoomInDuration
            self.zoomOutDuration = zoomOutDuration
            self.holdDuration = holdDuration
            self.boundingBoxPadding = boundingBoxPadding
            self.easingFunction = easingFunction
            self.maxZoomsPerMinute = maxZoomsPerMinute
            self.minTimeBetweenZooms = minTimeBetweenZooms
            self.zoomEnabled = zoomEnabled
        }

        /// Validate configuration values
        public func validate() throws {
            guard minZoomLevel >= 1.0 else {
                throw ZoomPlanError.invalidConfiguration("minZoomLevel must be >= 1.0 (no zoom out)")
            }
            guard maxZoomLevel > minZoomLevel else {
                throw ZoomPlanError.invalidConfiguration("maxZoomLevel must be > minZoomLevel")
            }
            guard maxZoomLevel <= 5.0 else {
                throw ZoomPlanError.invalidConfiguration("maxZoomLevel must be <= 5.0 (5x zoom max to prevent disorientation)")
            }
            guard defaultZoomLevel >= minZoomLevel && defaultZoomLevel <= maxZoomLevel else {
                throw ZoomPlanError.invalidConfiguration("defaultZoomLevel must be between minZoomLevel and maxZoomLevel")
            }
            guard zoomInDuration > 0 && zoomInDuration <= 2.0 else {
                throw ZoomPlanError.invalidConfiguration("zoomInDuration must be between 0 and 2 seconds")
            }
            guard zoomOutDuration > 0 && zoomOutDuration <= 2.0 else {
                throw ZoomPlanError.invalidConfiguration("zoomOutDuration must be between 0 and 2 seconds")
            }
            guard holdDuration >= 0 && holdDuration <= 5.0 else {
                throw ZoomPlanError.invalidConfiguration("holdDuration must be between 0 and 5 seconds")
            }
            guard boundingBoxPadding >= 0 && boundingBoxPadding <= 0.5 else {
                throw ZoomPlanError.invalidConfiguration("boundingBoxPadding must be between 0 and 0.5 (50%)")
            }
            guard maxZoomsPerMinute > 0 && maxZoomsPerMinute <= 20 else {
                throw ZoomPlanError.invalidConfiguration("maxZoomsPerMinute must be between 1 and 20")
            }
            guard minTimeBetweenZooms >= 1.0 && minTimeBetweenZooms <= 10.0 else {
                throw ZoomPlanError.invalidConfiguration("minTimeBetweenZooms must be between 1 and 10 seconds")
            }
        }

        /// Default configuration for tutorial/demo recordings
        public static func `default`() -> Configuration {
            return Configuration()
        }

        /// Subtle configuration - minimal zoom, slower transitions
        public static func subtle() -> Configuration {
            return Configuration(
                minZoomLevel: 1.0,
                maxZoomLevel: 1.8,
                defaultZoomLevel: 1.0,
                zoomInDuration: 0.8,
                zoomOutDuration: 1.0,
                holdDuration: 1.5,
                boundingBoxPadding: 0.2,
                easingFunction: .easeInOut,
                maxZoomsPerMinute: 4,
                minTimeBetweenZooms: 5.0,
                zoomEnabled: true
            )
        }

        /// Aggressive configuration - more zoom, faster transitions
        public static func aggressive() -> Configuration {
            return Configuration(
                minZoomLevel: 1.0,
                maxZoomLevel: 3.5,
                defaultZoomLevel: 1.0,
                zoomInDuration: 0.3,
                zoomOutDuration: 0.5,
                holdDuration: 0.5,
                boundingBoxPadding: 0.1,
                easingFunction: .easeOut,
                maxZoomsPerMinute: 10,
                minTimeBetweenZooms: 2.0,
                zoomEnabled: true
            )
        }

        /// Disabled zoom - no zoom events generated
        public static func disabled() -> Configuration {
            return Configuration(
                zoomEnabled: false
            )
        }
    }

    /// Easing functions for smooth zoom animations
    public enum EasingFunction: String, Codable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        case easeInQuad
        case easeOutQuad
        case easeInOutQuad
        case easeInCubic
        case easeOutCubic
        case easeInOutCubic

        /// Apply easing function to a progress value (0.0 to 1.0)
        func apply(to progress: Double) -> Double {
            let t = max(0.0, min(1.0, progress))
            switch self {
            case .linear:
                return t
            case .easeIn:
                return t * t
            case .easeOut:
                return t * (2.0 - t)
            case .easeInOut:
                return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
            case .easeInQuad:
                return t * t
            case .easeOutQuad:
                return t * (2.0 - t)
            case .easeInOutQuad:
                return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
            case .easeInCubic:
                return t * t * t
            case .easeOutCubic:
                return t * t * t + t * (t * (t - 1.0) - 1.0) + 1.0
            case .easeInOutCubic:
                return t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0
            }
        }
    }

    /// A single zoom keyframe
    public struct ZoomKeyframe: Codable, Identifiable, Equatable {
        /// Unique identifier
        public let id: UUID
        /// Timestamp in seconds from recording start
        public let timestamp: TimeInterval
        /// Zoom level at this keyframe (1.0 = no zoom, 2.0 = 2x zoom)
        public let zoomLevel: Double
        /// Focus point X (normalized 0.0-1.0, 0.5 = center)
        public let focusX: Double
        /// Focus point Y (normalized 0.0-1.0, 0.5 = center)
        public let focusY: Double
        /// Easing function to use for transition to next keyframe
        public let easing: EasingFunction

        public init(
            id: UUID = UUID(),
            timestamp: TimeInterval,
            zoomLevel: Double,
            focusX: Double,
            focusY: Double,
            easing: EasingFunction = .easeInOut
        ) {
            self.id = id
            self.timestamp = timestamp
            self.zoomLevel = zoomLevel
            self.focusX = focusX
            self.focusY = focusY
            self.easing = easing
        }
    }

    /// A zoom event representing a complete zoom-in, hold, and zoom-out cycle
    public struct ZoomEvent: Identifiable, Codable, Equatable {
        /// Unique identifier
        public let id: UUID
        /// Zoom-in start timestamp
        public let zoomInStartTime: TimeInterval
        /// Zoom-in end timestamp (zoom level reached)
        public let zoomInEndTime: TimeInterval
        /// Hold end timestamp (start zooming out)
        public let holdEndTime: TimeInterval
        /// Zoom-out end timestamp (back to default zoom)
        public let zoomOutEndTime: TimeInterval
        /// Target zoom level
        public let targetZoomLevel: Double
        /// Focus point X (normalized 0.0-1.0)
        public let focusX: Double
        /// Focus point Y (normalized 0.0-1.0)
        public let focusY: Double
        /// Click window that triggered this zoom
        public let clickWindowId: UUID
        /// Easing function for zoom transitions
        public let easing: EasingFunction

        /// Total duration of this zoom event
        public var totalDuration: TimeInterval {
            return zoomOutEndTime - zoomInStartTime
        }

        /// Zoom-in duration
        public var zoomInDuration: TimeInterval {
            return zoomInEndTime - zoomInStartTime
        }

        /// Hold duration
        public var holdDuration: TimeInterval {
            return holdEndTime - zoomInEndTime
        }

        /// Zoom-out duration
        public var zoomOutDuration: TimeInterval {
            return zoomOutEndTime - holdEndTime
        }

        public init(
            id: UUID = UUID(),
            zoomInStartTime: TimeInterval,
            zoomInEndTime: TimeInterval,
            holdEndTime: TimeInterval,
            zoomOutEndTime: TimeInterval,
            targetZoomLevel: Double,
            focusX: Double,
            focusY: Double,
            clickWindowId: UUID,
            easing: EasingFunction = .easeInOut
        ) {
            self.id = id
            self.zoomInStartTime = zoomInStartTime
            self.zoomInEndTime = zoomInEndTime
            self.holdEndTime = holdEndTime
            self.zoomOutEndTime = zoomOutEndTime
            self.targetZoomLevel = targetZoomLevel
            self.focusX = focusX
            self.focusY = focusY
            self.clickWindowId = clickWindowId
            self.easing = easing
        }

        /// Generate keyframes for this zoom event
        public func generateKeyframes(defaultZoomLevel: Double) -> [ZoomKeyframe] {
            let keyframeId = UUID()

            // Keyframe 1: Start zoom-in (at default zoom level)
            let startKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomInStartTime,
                zoomLevel: defaultZoomLevel,
                focusX: 0.5, // Center focus at start
                focusY: 0.5,
                easing: easing
            )

            // Keyframe 2: End zoom-in / Start hold (at target zoom level)
            let zoomInKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomInEndTime,
                zoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                easing: .linear // No easing during hold
            )

            // Keyframe 3: End hold / Start zoom-out (still at target zoom level)
            let holdKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: holdEndTime,
                zoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                easing: easing
            )

            // Keyframe 4: End zoom-out (back to default zoom level)
            let zoomOutKeyframe = ZoomKeyframe(
                id: keyframeId,
                timestamp: zoomOutEndTime,
                zoomLevel: defaultZoomLevel,
                focusX: 0.5, // Return to center focus
                focusY: 0.5,
                easing: .linear // No easing after zoom-out
            )

            return [startKeyframe, zoomInKeyframe, holdKeyframe, zoomOutKeyframe]
        }
    }

    /// Complete zoom plan with all zoom events and keyframes
    public struct ZoomPlan: Equatable {
        /// All zoom events in chronological order
        public let events: [ZoomEvent]
        /// All keyframes in chronological order (merged from all events)
        public let keyframes: [ZoomKeyframe]
        /// Configuration used to generate this plan
        public let configuration: Configuration
        /// Statistics about the zoom plan
        public let stats: ZoomPlanStats

        public init(
            events: [ZoomEvent],
            keyframes: [ZoomKeyframe],
            configuration: Configuration,
            stats: ZoomPlanStats
        ) {
            self.events = events
            self.keyframes = keyframes
            self.configuration = configuration
            self.stats = stats
        }

        /// Get zoom level at a specific timestamp (interpolated between keyframes)
        public func zoomLevel(at timestamp: TimeInterval) -> Double {
            guard !keyframes.isEmpty else { return configuration.defaultZoomLevel }

            // Find surrounding keyframes
            var previousKeyframe: ZoomKeyframe?
            var nextKeyframe: ZoomKeyframe?

            for keyframe in keyframes {
                if keyframe.timestamp <= timestamp {
                    previousKeyframe = keyframe
                } else if keyframe.timestamp > timestamp && nextKeyframe == nil {
                    nextKeyframe = keyframe
                    break
                }
            }

            // Handle edge cases
            guard let prev = previousKeyframe else {
                // Before first keyframe
                return keyframes.first?.zoomLevel ?? configuration.defaultZoomLevel
            }

            guard let next = nextKeyframe else {
                // After last keyframe
                return prev.zoomLevel
            }

            // Interpolate between keyframes
            let duration = next.timestamp - prev.timestamp
            guard duration > 0 else { return prev.zoomLevel }

            let progress = (timestamp - prev.timestamp) / duration
            let easedProgress = prev.easing.apply(to: progress)

            let zoomDelta = next.zoomLevel - prev.zoomLevel
            return prev.zoomLevel + (zoomDelta * easedProgress)
        }

        /// Get focus point at a specific timestamp (interpolated between keyframes)
        public func focusPoint(at timestamp: TimeInterval) -> CGPoint {
            guard !keyframes.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }

            // Find surrounding keyframes
            var previousKeyframe: ZoomKeyframe?
            var nextKeyframe: ZoomKeyframe?

            for keyframe in keyframes {
                if keyframe.timestamp <= timestamp {
                    previousKeyframe = keyframe
                } else if keyframe.timestamp > timestamp && nextKeyframe == nil {
                    nextKeyframe = keyframe
                    break
                }
            }

            // Handle edge cases
            guard let prev = previousKeyframe else {
                return CGPoint(x: keyframes.first?.focusX ?? 0.5, y: keyframes.first?.focusY ?? 0.5)
            }

            guard let next = nextKeyframe else {
                return CGPoint(x: prev.focusX, y: prev.focusY)
            }

            // Interpolate between keyframes
            let duration = next.timestamp - prev.timestamp
            guard duration > 0 else { return CGPoint(x: prev.focusX, y: prev.focusY) }

            let progress = (timestamp - prev.timestamp) / duration
            let easedProgress = prev.easing.apply(to: progress)

            let focusXDelta = next.focusX - prev.focusX
            let focusYDelta = next.focusY - prev.focusY

            return CGPoint(
                x: prev.focusX + (focusXDelta * easedProgress),
                y: prev.focusY + (focusYDelta * easedProgress)
            )
        }
    }

    /// Statistics about a zoom plan
    public struct ZoomPlanStats: Codable, Equatable {
        /// Total number of zoom events
        public let totalZoomEvents: Int
        /// Total number of keyframes
        public let totalKeyframes: Int
        /// Total time spent zoomed in (seconds)
        public let totalZoomedTime: TimeInterval
        /// Percentage of time spent zoomed
        public let zoomedTimePercentage: Double
        /// Average zoom level
        public let averageZoomLevel: Double
        /// Maximum zoom level reached
        public let maximumZoomLevel: Double
        /// Average time between zoom events
        public let averageTimeBetweenZooms: TimeInterval
        /// Zooms per minute
        public let zoomsPerMinute: Double
        /// Time range covered by zoom plan
        public let timeRange: ClosedRange<TimeInterval>

        public init(
            totalZoomEvents: Int,
            totalKeyframes: Int,
            totalZoomedTime: TimeInterval,
            zoomedTimePercentage: Double,
            averageZoomLevel: Double,
            maximumZoomLevel: Double,
            averageTimeBetweenZooms: TimeInterval,
            zoomsPerMinute: Double,
            timeRange: ClosedRange<TimeInterval>
        ) {
            self.totalZoomEvents = totalZoomEvents
            self.totalKeyframes = totalKeyframes
            self.totalZoomedTime = totalZoomedTime
            self.zoomedTimePercentage = zoomedTimePercentage
            self.averageZoomLevel = averageZoomLevel
            self.maximumZoomLevel = maximumZoomLevel
            self.averageTimeBetweenZooms = averageTimeBetweenZooms
            self.zoomsPerMinute = zoomsPerMinute
            self.timeRange = timeRange
        }
    }

    /// Zoom plan generation errors
    public enum ZoomPlanError: LocalizedError, Equatable {
        case invalidConfiguration(String)
        case noClickWindows
        case invalidClickWindows
        case zoomRateExceeded(Int, Int) // actual, maximum
        case invalidTimeline

        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return "Invalid zoom configuration: \(message)"
            case .noClickWindows:
                return "No click windows provided for zoom plan generation"
            case .invalidClickWindows:
                return "Invalid click windows data"
            case .zoomRateExceeded(let actual, let maximum):
                return "Zoom rate exceeded: \(actual) zooms/minute exceeds maximum of \(maximum)"
            case .invalidTimeline:
                return "Invalid timeline data for zoom plan"
            }
        }

        public static func == (lhs: ZoomPlanError, rhs: ZoomPlanError) -> Bool {
            switch (lhs, rhs) {
            case (.invalidConfiguration(let lhsMsg), .invalidConfiguration(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.noClickWindows, .noClickWindows):
                return true
            case (.invalidClickWindows, .invalidClickWindows):
                return true
            case (.zoomRateExceeded(let lhsActual, let lhsMax), .zoomRateExceeded(let rhsActual, let rhsMax)):
                return lhsActual == rhsActual && lhsMax == rhsMax
            case (.invalidTimeline, .invalidTimeline):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Generate a zoom plan from telemetry parser results
    /// - Parameters:
    ///   - parseResult: Result from TelemetryParser containing click windows
    ///   - config: Zoom plan generation configuration
    ///   - timelineDuration: Total timeline duration for stats calculation
    /// - Returns: ZoomPlan with zoom events and keyframes
    public func generateZoomPlan(
        from parseResult: TelemetryParser.ParseResult,
        config: Configuration = .default(),
        timelineDuration: TimeInterval? = nil
    ) async throws -> ZoomPlan {
        // Validate configuration
        try config.validate()

        // Check if zoom is enabled
        guard config.zoomEnabled else {
            return createEmptyZoomPlan(config: config)
        }

        // Get click windows from parse result
        let clickWindows = parseResult.windows

        guard !clickWindows.isEmpty else {
            throw ZoomPlanError.noClickWindows
        }

        // Sort windows by start time and filter by importance
        let sortedWindows = clickWindows.sorted { $0.startTime < $1.startTime }
        let filteredWindows = filterWindowsByImportance(sortedWindows)

        // Check zoom rate limits
        let duration = timelineDuration ?? (parseResult.stats.timeRange.upperBound - parseResult.stats.timeRange.lowerBound)
        try validateZoomRate(for: filteredWindows, duration: duration, config: config)

        // Generate zoom events from click windows
        var zoomEvents: [ZoomEvent] = []
        var lastZoomEndTime: TimeInterval = 0

        for window in filteredWindows {
            // Check minimum time between zooms
            if lastZoomEndTime > 0 && (window.startTime - lastZoomEndTime) < config.minTimeBetweenZooms {
                continue // Skip this zoom event (too soon after previous)
            }

            // Calculate zoom level based on bounding box size
            let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
            let normalizedArea = boundingBoxArea / 2_500_000.0 // Normalize for 1920x1080-ish screens
            let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: config)

            // Calculate focus point (center of click window)
            let focusX = window.centerPoint.x / 1920.0 // Normalize to 0-1 (assuming 1920 width)
            let focusY = window.centerPoint.y / 1080.0 // Normalize to 0-1 (assuming 1080 height)

            // Calculate timing
            let zoomInStart = window.startTime
            let zoomInEnd = zoomInStart + config.zoomInDuration
            let holdEnd = zoomInEnd + config.holdDuration
            let zoomOutEnd = holdEnd + config.zoomOutDuration

            // Create zoom event
            let zoomEvent = ZoomEvent(
                zoomInStartTime: zoomInStart,
                zoomInEndTime: zoomInEnd,
                holdEndTime: holdEnd,
                zoomOutEndTime: zoomOutEnd,
                targetZoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                clickWindowId: window.id,
                easing: config.easingFunction
            )

            zoomEvents.append(zoomEvent)
            lastZoomEndTime = zoomOutEnd
        }

        // Generate keyframes from zoom events
        let keyframes = generateKeyframes(from: zoomEvents, config: config)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: zoomEvents,
            keyframes: keyframes,
            config: config,
            duration: duration
        )

        return ZoomPlan(
            events: zoomEvents,
            keyframes: keyframes,
            configuration: config,
            stats: stats
        )
    }

    /// Generate a zoom plan from click windows directly (without parse result)
    /// - Parameters:
    ///   - clickWindows: Array of click windows from telemetry parser
    ///   - config: Zoom plan generation configuration
    ///   - timelineDuration: Total timeline duration for stats calculation
    /// - Returns: ZoomPlan with zoom events and keyframes
    public func generateZoomPlan(
        from clickWindows: [TelemetryParser.ClickWindow],
        config: Configuration = .default(),
        timelineDuration: TimeInterval
    ) async throws -> ZoomPlan {
        // Validate configuration
        try config.validate()

        // Check if zoom is enabled
        guard config.zoomEnabled else {
            return createEmptyZoomPlan(config: config)
        }

        guard !clickWindows.isEmpty else {
            throw ZoomPlanError.noClickWindows
        }

        // Sort windows by start time and filter by importance
        let sortedWindows = clickWindows.sorted { $0.startTime < $1.startTime }
        let filteredWindows = filterWindowsByImportance(sortedWindows)

        // Check zoom rate limits
        try validateZoomRate(for: filteredWindows, duration: timelineDuration, config: config)

        // Generate zoom events from click windows
        var zoomEvents: [ZoomEvent] = []
        var lastZoomEndTime: TimeInterval = 0

        for window in filteredWindows {
            // Check minimum time between zooms
            if lastZoomEndTime > 0 && (window.startTime - lastZoomEndTime) < config.minTimeBetweenZooms {
                continue // Skip this zoom event (too soon after previous)
            }

            // Calculate zoom level based on bounding box size
            let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
            let normalizedArea = boundingBoxArea / 2_500_000.0 // Normalize for 1920x1080-ish screens
            let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: config)

            // Calculate focus point (center of click window)
            let focusX = window.centerPoint.x / 1920.0 // Normalize to 0-1 (assuming 1920 width)
            let focusY = window.centerPoint.y / 1080.0 // Normalize to 0-1 (assuming 1080 height)

            // Calculate timing
            let zoomInStart = window.startTime
            let zoomInEnd = zoomInStart + config.zoomInDuration
            let holdEnd = zoomInEnd + config.holdDuration
            let zoomOutEnd = holdEnd + config.zoomOutDuration

            // Create zoom event
            let zoomEvent = ZoomEvent(
                zoomInStartTime: zoomInStart,
                zoomInEndTime: zoomInEnd,
                holdEndTime: holdEnd,
                zoomOutEndTime: zoomOutEnd,
                targetZoomLevel: targetZoomLevel,
                focusX: focusX,
                focusY: focusY,
                clickWindowId: window.id,
                easing: config.easingFunction
            )

            zoomEvents.append(zoomEvent)
            lastZoomEndTime = zoomOutEnd
        }

        // Generate keyframes from zoom events
        let keyframes = generateKeyframes(from: zoomEvents, config: config)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: zoomEvents,
            keyframes: keyframes,
            config: config,
            duration: timelineDuration
        )

        return ZoomPlan(
            events: zoomEvents,
            keyframes: keyframes,
            configuration: config,
            stats: stats
        )
    }

    // MARK: - Private Methods

    /// Create an empty zoom plan (when zoom is disabled)
    private func createEmptyZoomPlan(config: Configuration) -> ZoomPlan {
        let emptyStats = ZoomPlanStats(
            totalZoomEvents: 0,
            totalKeyframes: 0,
            totalZoomedTime: 0,
            zoomedTimePercentage: 0,
            averageZoomLevel: config.defaultZoomLevel,
            maximumZoomLevel: config.defaultZoomLevel,
            averageTimeBetweenZooms: 0,
            zoomsPerMinute: 0,
            timeRange: 0...0
        )

        return ZoomPlan(
            events: [],
            keyframes: [],
            configuration: config,
            stats: emptyStats
        )
    }

    /// Filter windows by importance (remove low-importance windows)
    private func filterWindowsByImportance(_ windows: [TelemetryParser.ClickWindow]) -> [TelemetryParser.ClickWindow] {
        guard windows.count > 1 else { return windows }

        // Calculate median importance score
        let sortedScores = windows.map { $0.importanceScore }.sorted()
        let medianIndex = sortedScores.count / 2
        let medianScore = sortedScores[medianIndex]

        // Filter to keep only windows above median importance
        return windows.filter { $0.importanceScore >= medianScore }
    }

    /// Validate zoom rate limits
    private func validateZoomRate(
        for windows: [TelemetryParser.ClickWindow],
        duration: TimeInterval,
        config: Configuration
    ) throws {
        guard duration > 0 else { return }

        let zoomsPerMinute = Double(windows.count) / (duration / 60.0)

        if zoomsPerMinute > Double(config.maxZoomsPerMinute) {
            throw ZoomPlanError.zoomRateExceeded(
                Int(zoomsPerMinute),
                config.maxZoomsPerMinute
            )
        }
    }

    /// Calculate zoom level based on bounding box area
    private func calculateZoomLevel(for normalizedArea: Double, config: Configuration) -> Double {
        // Smaller area = higher zoom level
        // Larger area = lower zoom level

        // Map area to zoom level (inverse relationship)
        // Area range: ~0.01 (small click cluster) to ~1.0 (full screen)
        // Zoom range: config.minZoomLevel to config.maxZoomLevel

        let clampedArea = max(0.01, min(1.0, normalizedArea))

        // Inverse mapping: smaller area -> higher zoom
        let zoomRange = config.maxZoomLevel - config.minZoomLevel
        let zoomLevel = config.maxZoomLevel - (clampedArea * zoomRange)

        return max(config.minZoomLevel, min(config.maxZoomLevel, zoomLevel))
    }

    /// Generate keyframes from zoom events
    private func generateKeyframes(from zoomEvents: [ZoomEvent], config: Configuration) -> [ZoomKeyframe] {
        var allKeyframes: [ZoomKeyframe] = []

        for event in zoomEvents {
            let eventKeyframes = event.generateKeyframes(defaultZoomLevel: config.defaultZoomLevel)
            allKeyframes.append(contentsOf: eventKeyframes)
        }

        // Sort by timestamp
        return allKeyframes.sorted { $0.timestamp < $1.timestamp }
    }

    /// Calculate zoom plan statistics
    private func calculateZoomPlanStats(
        events: [ZoomEvent],
        keyframes: [ZoomKeyframe],
        config: Configuration,
        duration: TimeInterval
    ) -> ZoomPlanStats {
        guard !events.isEmpty else {
            return ZoomPlanStats(
                totalZoomEvents: 0,
                totalKeyframes: 0,
                totalZoomedTime: 0,
                zoomedTimePercentage: 0,
                averageZoomLevel: config.defaultZoomLevel,
                maximumZoomLevel: config.defaultZoomLevel,
                averageTimeBetweenZooms: 0,
                zoomsPerMinute: 0,
                timeRange: 0...duration
            )
        }

        // Calculate total zoomed time
        let totalZoomedTime = events.reduce(0) { $0 + $1.totalDuration }
        let zoomedTimePercentage = duration > 0 ? (totalZoomedTime / duration) * 100 : 0

        // Calculate average and max zoom levels
        let zoomLevels = events.map { $0.targetZoomLevel }
        let averageZoomLevel = zoomLevels.reduce(0, +) / Double(zoomLevels.count)
        let maximumZoomLevel = zoomLevels.max() ?? config.defaultZoomLevel

        // Calculate average time between zooms
        let averageTimeBetweenZooms: TimeInterval
        if events.count > 1 {
            let intervals = zip(events, events.dropFirst()).map { $1.zoomInStartTime - $0.zoomOutEndTime }
            averageTimeBetweenZooms = intervals.reduce(0, +) / Double(intervals.count)
        } else {
            averageTimeBetweenZooms = 0
        }

        // Calculate zooms per minute
        let zoomsPerMinute = duration > 0 ? Double(events.count) / (duration / 60.0) : 0

        // Time range
        let timeRange = 0...duration

        return ZoomPlanStats(
            totalZoomEvents: events.count,
            totalKeyframes: keyframes.count,
            totalZoomedTime: totalZoomedTime,
            zoomedTimePercentage: zoomedTimePercentage,
            averageZoomLevel: averageZoomLevel,
            maximumZoomLevel: maximumZoomLevel,
            averageTimeBetweenZooms: averageTimeBetweenZooms,
            zoomsPerMinute: zoomsPerMinute,
            timeRange: timeRange
        )
    }

    /// Generate a zoom plan with per-segment configuration (Épica I, Task 4)
    /// This method respects per-segment zoom settings and generates appropriate zoom plans for each section
    /// - Parameters:
    ///   - parseResult: Result from TelemetryParser containing click windows
    ///   - segments: Timeline segments with their zoom configurations
    ///   - defaultConfig: Default zoom configuration for segments without explicit settings
    ///   - timelineDuration: Total timeline duration for stats calculation
    /// - Returns: ZoomPlan with zoom events and keyframes respecting per-segment settings
    public func generateZoomPlanWithSections(
        from parseResult: TelemetryParser.ParseResult,
        segments: [Project.Timeline.Segment],
        defaultConfig: Configuration = .default(),
        timelineDuration: TimeInterval? = nil
    ) async throws -> ZoomPlan {
        let duration = timelineDuration ?? (parseResult.stats.timeRange.upperBound - parseResult.stats.timeRange.lowerBound)

        // Filter click windows by segment and generate zoom events for each segment
        var allZoomEvents: [ZoomEvent] = []
        var allKeyframes: [ZoomKeyframe] = []

        for segment in segments {
            // Get effective configuration for this segment
            let segmentConfig: Configuration
            if let zoomConfig = segment.zoom {
                if let intensity = zoomConfig.intensity {
                    segmentConfig = intensity.toConfiguration(base: defaultConfig)
                } else {
                    // Use custom configuration from segment
                    segmentConfig = Configuration(
                        minZoomLevel: zoomConfig.minZoomLevel,
                        maxZoomLevel: zoomConfig.maxZoomLevel,
                        defaultZoomLevel: defaultConfig.defaultZoomLevel,
                        zoomInDuration: defaultConfig.zoomInDuration,
                        zoomOutDuration: defaultConfig.zoomOutDuration,
                        holdDuration: defaultConfig.holdDuration,
                        boundingBoxPadding: defaultConfig.boundingBoxPadding,
                        easingFunction: defaultConfig.easingFunction,
                        maxZoomsPerMinute: defaultConfig.maxZoomsPerMinute,
                        minTimeBetweenZooms: defaultConfig.minTimeBetweenZooms,
                        zoomEnabled: zoomConfig.enabled
                    )
                }
            } else {
                segmentConfig = defaultConfig
            }

            // Skip zoom generation for this segment if disabled
            guard segmentConfig.zoomEnabled else {
                continue
            }

            // Get click windows that fall within this segment's timeline range
            let segmentClickWindows = parseResult.windows.filter { window in
                window.startTime >= segment.timelineIn && window.startTime <= segment.timelineOut
            }

            // Skip if no click windows in this segment
            guard !segmentClickWindows.isEmpty else {
                continue
            }

            // Sort windows by start time and filter by importance
            let sortedWindows = segmentClickWindows.sorted { $0.startTime < $1.startTime }
            let filteredWindows = filterWindowsByImportance(sortedWindows)

            // Check zoom rate limits for this segment
            let segmentDuration = segment.timelineOut - segment.timelineIn
            try validateZoomRate(for: filteredWindows, duration: segmentDuration, config: segmentConfig)

            // Generate zoom events for this segment
            var lastZoomEndTime: TimeInterval = segment.timelineIn

            for window in filteredWindows {
                // Check minimum time between zooms
                if lastZoomEndTime > segment.timelineIn && (window.startTime - lastZoomEndTime) < segmentConfig.minTimeBetweenZooms {
                    continue // Skip this zoom event (too soon after previous)
                }

                // Calculate zoom level based on bounding box size
                let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
                let normalizedArea = boundingBoxArea / 2_500_000.0
                let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: segmentConfig)

                // Calculate focus point
                let focusX = window.centerPoint.x / 1920.0
                let focusY = window.centerPoint.y / 1080.0

                // Calculate timing (all times are in timeline coordinates)
                let zoomInStart = window.startTime
                let zoomInEnd = zoomInStart + segmentConfig.zoomInDuration
                let holdEnd = zoomInEnd + segmentConfig.holdDuration
                let zoomOutEnd = holdEnd + segmentConfig.zoomOutDuration

                // Create zoom event
                let zoomEvent = ZoomEvent(
                    zoomInStartTime: zoomInStart,
                    zoomInEndTime: zoomInEnd,
                    holdEndTime: holdEnd,
                    zoomOutEndTime: zoomOutEnd,
                    targetZoomLevel: targetZoomLevel,
                    focusX: focusX,
                    focusY: focusY,
                    clickWindowId: window.id,
                    easing: segmentConfig.easingFunction
                )

                allZoomEvents.append(zoomEvent)
                lastZoomEndTime = zoomOutEnd
            }
        }

        // Generate keyframes from all zoom events
        allKeyframes = generateKeyframes(from: allZoomEvents, config: defaultConfig)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: allZoomEvents,
            keyframes: allKeyframes,
            config: defaultConfig,
            duration: duration
        )

        return ZoomPlan(
            events: allZoomEvents,
            keyframes: allKeyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }

    /// Generate a zoom plan with per-segment configuration from click windows directly
    /// This is a convenience method that doesn't require a ParseResult
    /// - Parameters:
    ///   - clickWindows: Array of click windows from telemetry parser
    ///   - segments: Timeline segments with their zoom configurations
    ///   - defaultConfig: Default zoom configuration for segments without explicit settings
    ///   - timelineDuration: Total timeline duration for stats calculation
    /// - Returns: ZoomPlan with zoom events and keyframes respecting per-segment settings
    public func generateZoomPlanWithSections(
        from clickWindows: [TelemetryParser.ClickWindow],
        segments: [Project.Timeline.Segment],
        defaultConfig: Configuration = .default(),
        timelineDuration: TimeInterval
    ) async throws -> ZoomPlan {
        // Filter click windows by segment and generate zoom events for each segment
        var allZoomEvents: [ZoomEvent] = []
        var allKeyframes: [ZoomKeyframe] = []

        for segment in segments {
            // Get effective configuration for this segment
            let segmentConfig: Configuration
            if let zoomConfig = segment.zoom {
                if let intensity = zoomConfig.intensity {
                    segmentConfig = intensity.toConfiguration(base: defaultConfig)
                } else {
                    // Use custom configuration from segment
                    segmentConfig = Configuration(
                        minZoomLevel: zoomConfig.minZoomLevel,
                        maxZoomLevel: zoomConfig.maxZoomLevel,
                        defaultZoomLevel: defaultConfig.defaultZoomLevel,
                        zoomInDuration: defaultConfig.zoomInDuration,
                        zoomOutDuration: defaultConfig.zoomOutDuration,
                        holdDuration: defaultConfig.holdDuration,
                        boundingBoxPadding: defaultConfig.boundingBoxPadding,
                        easingFunction: defaultConfig.easingFunction,
                        maxZoomsPerMinute: defaultConfig.maxZoomsPerMinute,
                        minTimeBetweenZooms: defaultConfig.minTimeBetweenZooms,
                        zoomEnabled: zoomConfig.enabled
                    )
                }
            } else {
                segmentConfig = defaultConfig
            }

            // Skip zoom generation for this segment if disabled
            guard segmentConfig.zoomEnabled else {
                continue
            }

            // Get click windows that fall within this segment's timeline range
            let segmentClickWindows = clickWindows.filter { window in
                window.startTime >= segment.timelineIn && window.startTime <= segment.timelineOut
            }

            // Skip if no click windows in this segment
            guard !segmentClickWindows.isEmpty else {
                continue
            }

            // Sort windows by start time and filter by importance
            let sortedWindows = segmentClickWindows.sorted { $0.startTime < $1.startTime }
            let filteredWindows = filterWindowsByImportance(sortedWindows)

            // Check zoom rate limits for this segment
            let segmentDuration = segment.timelineOut - segment.timelineIn
            try validateZoomRate(for: filteredWindows, duration: segmentDuration, config: segmentConfig)

            // Generate zoom events for this segment
            var lastZoomEndTime: TimeInterval = segment.timelineIn

            for window in filteredWindows {
                // Check minimum time between zooms
                if lastZoomEndTime > segment.timelineIn && (window.startTime - lastZoomEndTime) < segmentConfig.minTimeBetweenZooms {
                    continue
                }

                // Calculate zoom level based on bounding box size
                let boundingBoxArea = Double(window.boundingBox.width * window.boundingBox.height)
                let normalizedArea = boundingBoxArea / 2_500_000.0
                let targetZoomLevel = calculateZoomLevel(for: normalizedArea, config: segmentConfig)

                // Calculate focus point
                let focusX = window.centerPoint.x / 1920.0
                let focusY = window.centerPoint.y / 1080.0

                // Calculate timing
                let zoomInStart = window.startTime
                let zoomInEnd = zoomInStart + segmentConfig.zoomInDuration
                let holdEnd = zoomInEnd + segmentConfig.holdDuration
                let zoomOutEnd = holdEnd + segmentConfig.zoomOutDuration

                // Create zoom event
                let zoomEvent = ZoomEvent(
                    zoomInStartTime: zoomInStart,
                    zoomInEndTime: zoomInEnd,
                    holdEndTime: holdEnd,
                    zoomOutEndTime: zoomOutEnd,
                    targetZoomLevel: targetZoomLevel,
                    focusX: focusX,
                    focusY: focusY,
                    clickWindowId: window.id,
                    easing: segmentConfig.easingFunction
                )

                allZoomEvents.append(zoomEvent)
                lastZoomEndTime = zoomOutEnd
            }
        }

        // Generate keyframes from all zoom events
        allKeyframes = generateKeyframes(from: allZoomEvents, config: defaultConfig)

        // Calculate statistics
        let stats = calculateZoomPlanStats(
            events: allZoomEvents,
            keyframes: allKeyframes,
            config: defaultConfig,
            duration: timelineDuration
        )

        return ZoomPlan(
            events: allZoomEvents,
            keyframes: allKeyframes,
            configuration: defaultConfig,
            stats: stats
        )
    }
}
