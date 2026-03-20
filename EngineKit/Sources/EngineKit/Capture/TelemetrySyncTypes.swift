//
//  TelemetrySyncTypes.swift
//  EngineKit
//
//  Extracted from TelemetrySync.swift — types, configuration, and errors
//

import Foundation

extension TelemetrySync {
    /// Synchronization result
    public struct SyncResult {
        public let events: [SyncedEvent]
        public let validation: ValidationResult
        public let stats: SyncStats

        public init(events: [SyncedEvent], validation: ValidationResult, stats: SyncStats) {
            self.events = events
            self.validation = validation
            self.stats = stats
        }
    }

    /// Synchronized telemetry event with timeline information
    public struct SyncedEvent: Identifiable {
        public let id: UUID
        public let event: TelemetryRecorder.Event
        public let timelineTimestamp: TimeInterval
        public let sourceTimestamp: TimeInterval
        public let segmentId: String?

        public init(
            id: UUID = UUID(),
            event: TelemetryRecorder.Event,
            timelineTimestamp: TimeInterval,
            sourceTimestamp: TimeInterval,
            segmentId: String? = nil
        ) {
            self.id = id
            self.event = event
            self.timelineTimestamp = timelineTimestamp
            self.sourceTimestamp = sourceTimestamp
            self.segmentId = segmentId
        }
    }

    /// Validation result for telemetry synchronization
    public struct ValidationResult {
        public let isValid: Bool
        public let syncOffsetMs: Double
        public let drift: DriftInfo?
        public let missingSegments: [MissingSegment]
        public let warnings: [ValidationWarning]

        public init(
            isValid: Bool,
            syncOffsetMs: Double,
            drift: DriftInfo? = nil,
            missingSegments: [MissingSegment] = [],
            warnings: [ValidationWarning] = []
        ) {
            self.isValid = isValid
            self.syncOffsetMs = syncOffsetMs
            self.drift = drift
            self.missingSegments = missingSegments
            self.warnings = warnings
        }
    }

    /// Drift information
    public struct DriftInfo {
        public let maxDriftMs: Double
        public let avgDriftMs: Double
        public let maxDriftTimestamp: TimeInterval
        public let isExcessive: Bool

        public init(maxDriftMs: Double, avgDriftMs: Double, maxDriftTimestamp: TimeInterval, isExcessive: Bool) {
            self.maxDriftMs = maxDriftMs
            self.avgDriftMs = avgDriftMs
            self.maxDriftTimestamp = maxDriftTimestamp
            self.isExcessive = isExcessive
        }
    }

    /// Missing telemetry segment
    public struct MissingSegment {
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let duration: TimeInterval

        public init(startTime: TimeInterval, endTime: TimeInterval) {
            self.startTime = startTime
            self.endTime = endTime
            self.duration = endTime - startTime
        }
    }

    /// Validation warning type
    public struct WarningType: Equatable {
        public static let lowEventCount = WarningType("low_event_count")
        public static let irregularSampling = WarningType("irregular_sampling")
        public static let missingClickEvents = WarningType("missing_click_events")

        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Validation warning
    public struct ValidationWarning: Equatable {
        public let type: WarningType
        public let message: String
        public let timestamp: TimeInterval?

        public init(type: WarningType, message: String, timestamp: TimeInterval? = nil) {
            self.type = type
            self.message = message
            self.timestamp = timestamp
        }
    }

    /// Synchronization statistics
    public struct SyncStats {
        public let totalEvents: Int
        public let moveEvents: Int
        public let clickEvents: Int
        public let scrollEvents: Int
        public let eventsPerSecond: Double
        public let timeRange: ClosedRange<TimeInterval>

        public init(
            totalEvents: Int,
            moveEvents: Int,
            clickEvents: Int,
            scrollEvents: Int,
            eventsPerSecond: Double,
            timeRange: ClosedRange<TimeInterval>
        ) {
            self.totalEvents = totalEvents
            self.moveEvents = moveEvents
            self.clickEvents = clickEvents
            self.scrollEvents = scrollEvents
            self.eventsPerSecond = eventsPerSecond
            self.timeRange = timeRange
        }
    }

    /// Debug overlay data
    public struct DebugOverlay {
        public struct CursorPosition {
            public let x: Int
            public let y: Int
            public let timestamp: TimeInterval
            public let displayID: String?
        }

        public struct ClickEvent {
            public let x: Int
            public let y: Int
            public let button: Int
            public let isDown: Bool
            public let timestamp: TimeInterval
        }

        public let cursorPositions: [CursorPosition]
        public let clickEvents: [ClickEvent]
        public let timeRange: ClosedRange<TimeInterval>

        public init(
            cursorPositions: [CursorPosition],
            clickEvents: [ClickEvent],
            timeRange: ClosedRange<TimeInterval>
        ) {
            self.cursorPositions = cursorPositions
            self.clickEvents = clickEvents
            self.timeRange = timeRange
        }

        /// Get cursor position at specific timestamp (interpolated)
        public func cursorPosition(at timestamp: TimeInterval) -> CursorPosition? {
            guard let before = cursorPositions.last(where: { $0.timestamp <= timestamp }),
                  let after = cursorPositions.first(where: { $0.timestamp >= timestamp }) else {
                return cursorPositions.min(by: { a, b in
                    abs(a.timestamp - timestamp) < abs(b.timestamp - timestamp)
                })
            }

            if before.timestamp == after.timestamp {
                return before
            }

            let progress = (timestamp - before.timestamp) / (after.timestamp - before.timestamp)
            return CursorPosition(
                x: Int(Double(before.x) + progress * Double(after.x - before.x)),
                y: Int(Double(before.y) + progress * Double(after.y - before.y)),
                timestamp: timestamp,
                displayID: before.displayID
            )
        }

        /// Get click events in time range
        public func clickEvents(in range: ClosedRange<TimeInterval>) -> [ClickEvent] {
            return clickEvents.filter { range.contains($0.timestamp) }
        }
    }

    /// Synchronization errors
    public enum SyncError: LocalizedError {
        case fileNotFound(URL)
        case invalidTelemetryData
        case parseError(String)
        case timelineNotAvailable
        case invalidSegment

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "Telemetry file not found: \(url.path)"
            case .invalidTelemetryData:
                return "Invalid telemetry data format"
            case .parseError(let message):
                return "Failed to parse telemetry: \(message)"
            case .timelineNotAvailable:
                return "Timeline information not available"
            case .invalidSegment:
                return "Invalid timeline segment"
            }
        }
    }

    /// Synchronization configuration
    public struct Configuration {
        public let acceptableDriftMs: Double
        public let detectGaps: Bool
        public let minGapDuration: TimeInterval
        public let minExpectedEventsPerSecond: Double

        public init(
            acceptableDriftMs: Double = 100.0,
            detectGaps: Bool = true,
            minGapDuration: TimeInterval = 0.5,
            minExpectedEventsPerSecond: Double = 10.0
        ) {
            self.acceptableDriftMs = acceptableDriftMs
            self.detectGaps = detectGaps
            self.minGapDuration = minGapDuration
            self.minExpectedEventsPerSecond = minExpectedEventsPerSecond
        }

        public static let `default` = Configuration()

        public static let strict = Configuration(
            acceptableDriftMs: 50.0,
            detectGaps: true,
            minGapDuration: 0.1,
            minExpectedEventsPerSecond: 20.0
        )

        public static let lenient = Configuration(
            acceptableDriftMs: 200.0,
            detectGaps: false,
            minGapDuration: 1.0,
            minExpectedEventsPerSecond: 5.0
        )
    }
}

// MARK: - Array Extensions for Statistics

extension Array where Element == TimeInterval {
    var mean: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double? {
        guard let mean = mean, count > 1 else { return nil }
        let variance = map { pow($0 - mean, 2) }.reduce(0, +) / Double(count - 1)
        return sqrt(variance)
    }
}
