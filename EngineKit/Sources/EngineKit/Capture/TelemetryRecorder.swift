//
//  TelemetryRecorder.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AppKit

/// TelemetryRecorder captures cursor movement, clicks, and scroll events
public actor TelemetryRecorder {
    // MARK: - Types

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

    // MARK: - Properties

    private var currentSession: RecordingSession?
    private var eventMonitor: Any?
    private var scrollMonitor: Any?
    private var fileHandle: FileHandle?
    private var lastMoveTime: TimeInterval = 0
    private var lastMovePosition: CGPoint = .zero
    private var durationTimer: Task<Void, Never>?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Start recording telemetry
    public func startRecording(config: Configuration) async throws -> RecordingSession {
        guard currentSession == nil else {
            throw TelemetryError.alreadyRecording
        }

        // Create telemetry directory
        let telemetryDirectory = config.outputDirectory.appendingPathComponent("telemetry")
        try FileManager.default.createDirectory(at: telemetryDirectory, withIntermediateDirectories: true)

        // Create cursor.jsonl file
        let cursorFilePath = telemetryDirectory.appendingPathComponent("cursor.jsonl")
        FileManager.default.createFile(atPath: cursorFilePath.path, contents: nil)

        guard let fileHandle = FileHandle(forWritingAtPath: cursorFilePath.path) else {
            throw TelemetryError.fileCreationFailed(cursorFilePath)
        }

        self.fileHandle = fileHandle

        // Create session
        let session = RecordingSession(config: config)
        session.markStarted(at: Date())
        currentSession = session

        // Setup event monitoring
        setupEventMonitoring(config: config)

        // Start duration timer
        startDurationTimer()

        return session
    }

    /// Stop recording telemetry
    public func stopRecording() async throws -> RecordingResult {
        guard let session = currentSession else {
            throw TelemetryError.notRecording
        }

        // Stop event monitoring
        stopEventMonitoring()

        // Stop duration timer
        stopDurationTimer()

        // Close file handle
        try fileHandle?.close()
        fileHandle = nil

        // Mark session as ended
        session.markEnded(at: Date())

        // Build result
        let cursorFilePath = session.config.outputDirectory
            .appendingPathComponent("telemetry")
            .appendingPathComponent("cursor.jsonl")

        let result = RecordingResult(
            sessionID: session.id,
            cursorFilePath: cursorFilePath,
            eventCount: session.eventCount,
            duration: session.duration
        )

        currentSession = nil

        return result
    }

    /// Get current recording session
    public func getCurrentSession() -> RecordingSession? {
        return currentSession
    }

    /// Check if currently recording
    public func isRecording() -> Bool {
        return currentSession?.isRecording ?? false
    }

    // MARK: - Private Methods

    private func setupEventMonitoring(config: Configuration) {
        // Calculate throttle interval based on frequency
        _ = 1.0 / config.cursorMoveFrequency

        // Monitor mouse movement and clicks
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
            Task {
                guard let self = self, await self.isRecording() else {
                    return
                }

                await self.handleMouseEvent(event, config: config)
            }
        }

        // Monitor scroll events if enabled
        if config.captureScroll {
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                Task {
                    guard let self = self, await self.isRecording() else {
                        return
                    }

                    await self.handleScrollEvent(event, config: config)
                }
            }
        }
    }

    private func stopEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent, config: Configuration) async {
        guard let session = currentSession, let startTime = session.startTime else {
            return
        }

        let location = event.locationInWindow
        let timestamp = Date().timeIntervalSince(startTime)

        // Get display ID if enabled
        var displayID: String? = nil
        if config.captureDisplayID {
            let screen = NSScreen.screens.first { screen in
                screen.frame.contains(location)
            }
            displayID = screen?.localizedName
        }

        let eventTypes: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]

        if eventTypes.contains(event.type) {
            // Handle click events (down/up)
            let eventType: EventType
            let button: Int

            switch event.type {
            case .leftMouseDown:
                eventType = .down
                button = 0
            case .leftMouseUp:
                eventType = .up
                button = 0
            case .rightMouseDown:
                eventType = .down
                button = 1
            case .rightMouseUp:
                eventType = .up
                button = 1
            case .otherMouseDown:
                eventType = .down
                button = Int(event.buttonNumber)
            case .otherMouseUp:
                eventType = .up
                button = Int(event.buttonNumber)
            default:
                return
            }

            let telemetryEvent = Event(
                t: timestamp,
                type: eventType,
                x: Int(location.x),
                y: Int(location.y),
                button: button,
                displayID: displayID
            )

            await writeEvent(telemetryEvent)
        } else {
            // Handle movement events (throttled)
            let currentTime = timestamp
            let throttleInterval = 1.0 / config.cursorMoveFrequency

            if currentTime - lastMoveTime >= throttleInterval {
                // Check if position changed significantly (avoid duplicates)
                let deltaX = abs(location.x - lastMovePosition.x)
                let deltaY = abs(location.y - lastMovePosition.y)

                if deltaX > 0.1 || deltaY > 0.1 {
                    lastMoveTime = currentTime
                    lastMovePosition = location

                    let telemetryEvent = Event(
                        t: timestamp,
                        type: .move,
                        x: Int(location.x),
                        y: Int(location.y),
                        displayID: displayID
                    )

                    await writeEvent(telemetryEvent)
                }
            }
        }
    }

    private func handleScrollEvent(_ event: NSEvent, config: Configuration) async {
        guard let session = currentSession, let startTime = session.startTime else {
            return
        }

        let location = event.locationInWindow
        let timestamp = Date().timeIntervalSince(startTime)

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        // Only record if there's actual scrolling
        if abs(dx) > 0.01 || abs(dy) > 0.01 {
            // Get display ID if enabled
            var displayID: String? = nil
            if config.captureDisplayID {
                let screen = NSScreen.screens.first { screen in
                    screen.frame.contains(location)
                }
                displayID = screen?.localizedName
            }

            let telemetryEvent = Event(
                t: timestamp,
                type: .scroll,
                x: Int(location.x),
                y: Int(location.y),
                dx: dx,
                dy: dy,
                displayID: displayID
            )

            await writeEvent(telemetryEvent)
        }
    }

    private func writeEvent(_ event: Event) async {
        guard let fileHandle = fileHandle, let session = currentSession else {
            return
        }

        do {
            let jsonl = try event.toJSONL()
            let line = jsonl + "\n"
            if let data = line.data(using: .utf8) {
                fileHandle.write(data)
                session.incrementEventCount()
            }
        } catch {
            session.setError(error)
        }
    }

    private func startDurationTimer() {
        durationTimer = Task {
            while !Task.isCancelled, let session = currentSession, let startTime = session.startTime {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                let elapsed = Date().timeIntervalSince(startTime)
                session.updateDuration(elapsed)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = nil
    }
}
