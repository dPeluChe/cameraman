//
//  TelemetryRecorderTypes.swift
//  EngineKit
//
//  Extracted from TelemetryRecorder.swift — types, configuration, and errors
//

import Foundation

extension TelemetryRecorder {
    /// Configuration for telemetry recording
    public struct Configuration {
        /// Output directory for telemetry files
        public let outputDirectory: URL
        /// Throttle frequency for cursor movement events (Hz)
        public let cursorMoveFrequency: Double
        /// Whether to capture scroll events
        public let captureScroll: Bool
        /// Whether to capture display ID (for multi-monitor setups)
        public let captureDisplayID: Bool

        public init(
            outputDirectory: URL,
            cursorMoveFrequency: Double = 60.0,
            captureScroll: Bool = false,
            captureDisplayID: Bool = false
        ) {
            self.outputDirectory = outputDirectory
            self.cursorMoveFrequency = cursorMoveFrequency
            self.captureScroll = captureScroll
            self.captureDisplayID = captureDisplayID
        }

        /// Default configuration for single-monitor setup
        public static func `default`(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                cursorMoveFrequency: 60.0,
                captureScroll: false,
                captureDisplayID: false
            )
        }

        /// Configuration with scroll tracking enabled
        public static func withScrollTracking(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                cursorMoveFrequency: 60.0,
                captureScroll: true,
                captureDisplayID: false
            )
        }

        /// Configuration for multi-monitor setup
        public static func multiMonitor(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                cursorMoveFrequency: 60.0,
                captureScroll: false,
                captureDisplayID: true
            )
        }
    }

    /// Telemetry event types
    public enum EventType: String, Codable, Equatable {
        case move
        case down
        case up
        case scroll
    }

    /// Telemetry event
    public struct Event: Codable {
        /// Timestamp in seconds from recording start
        public let t: Double
        /// Event type
        public let type: EventType
        /// Cursor X position (screen coordinates)
        public let x: Int
        /// Cursor Y position (screen coordinates)
        public let y: Int
        /// Mouse button (for click events: 0=left, 1=right, 2=middle)
        public let button: Int?
        /// Scroll delta X (for scroll events)
        public let dx: Double?
        /// Scroll delta Y (for scroll events)
        public let dy: Double?
        /// Display ID (for multi-monitor setups)
        public let displayID: String?

        public init(
            t: Double,
            type: EventType,
            x: Int,
            y: Int,
            button: Int? = nil,
            dx: Double? = nil,
            dy: Double? = nil,
            displayID: String? = nil
        ) {
            self.t = t
            self.type = type
            self.x = x
            self.y = y
            self.button = button
            self.dx = dx
            self.dy = dy
            self.displayID = displayID
        }

        /// Convert event to JSONL string
        func toJSONL() throws -> String {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw TelemetryError.encodingFailed
            }
            return jsonString
        }
    }

    /// Active recording session
    public final class RecordingSession: Identifiable {
        public let id: UUID
        public private(set) var isRecording: Bool = false
        public private(set) var startTime: Date?
        public private(set) var endTime: Date?
        public private(set) var duration: TimeInterval = 0
        public private(set) var eventCount: Int = 0
        public private(set) var error: Error?

        internal let config: TelemetryRecorder.Configuration

        internal init(id: UUID = UUID(), config: TelemetryRecorder.Configuration) {
            self.id = id
            self.config = config
        }

        internal func markStarted(at time: Date) {
            self.startTime = time
            self.isRecording = true
        }

        internal func markEnded(at time: Date) {
            self.endTime = time
            self.isRecording = false
            if let start = startTime {
                self.duration = time.timeIntervalSince(start)
            }
        }

        internal func updateDuration(_ elapsed: TimeInterval) {
            self.duration = elapsed
        }

        internal func incrementEventCount() {
            self.eventCount += 1
        }

        internal func setError(_ error: Error) {
            self.error = error
            self.isRecording = false
        }
    }

    /// Recording result
    public struct RecordingResult {
        /// Session ID
        public let sessionID: UUID
        /// Path to cursor telemetry file
        public let cursorFilePath: URL
        /// Number of events recorded
        public let eventCount: Int
        /// Recording duration
        public let duration: TimeInterval

        public init(
            sessionID: UUID,
            cursorFilePath: URL,
            eventCount: Int,
            duration: TimeInterval
        ) {
            self.sessionID = sessionID
            self.cursorFilePath = cursorFilePath
            self.eventCount = eventCount
            self.duration = duration
        }
    }

    /// Telemetry recorder errors
    public enum TelemetryError: LocalizedError {
        case alreadyRecording
        case notRecording
        case directoryCreationFailed(URL)
        case fileCreationFailed(URL)
        case writeFailed
        case encodingFailed
        case invalidConfiguration

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "A telemetry recording session is already in progress"
            case .notRecording:
                return "No telemetry recording session is in progress"
            case .directoryCreationFailed(let url):
                return "Failed to create telemetry directory: \(url.path)"
            case .fileCreationFailed(let url):
                return "Failed to create telemetry file: \(url.path)"
            case .writeFailed:
                return "Failed to write telemetry data"
            case .encodingFailed:
                return "Failed to encode telemetry event"
            case .invalidConfiguration:
                return "Invalid telemetry configuration"
            }
        }
    }
}
