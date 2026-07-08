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
    // MARK: - Properties

    private var currentSession: RecordingSession?
    @MainActor
    private var eventMonitor: Any?
    @MainActor
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

        // Write cursor.jsonl directly into the output directory supplied by the caller.
        // Previously we appended a second "telemetry" component here, which produced
        // `<outputDir>/telemetry/cursor.jsonl` when `outputDir` was already the telemetry
        // folder — the Recorder then looked one level up and never found the file.
        try FileManager.default.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)

        let cursorFilePath = config.outputDirectory.appendingPathComponent("cursor.jsonl")
        FileManager.default.createFile(atPath: cursorFilePath.path, contents: nil)

        guard let fileHandle = FileHandle(forWritingAtPath: cursorFilePath.path) else {
            throw TelemetryError.fileCreationFailed(cursorFilePath)
        }

        self.fileHandle = fileHandle

        // Create session
        let session = RecordingSession(config: config)
        session.markStarted(at: Date())
        currentSession = session

        // Setup event monitoring on the main actor; AppKit global event monitors
        // must be installed from the main thread to receive events reliably.
        await setupEventMonitoring(config: config)

        // Start duration timer
        startDurationTimer()

        return session
    }

    /// Stop recording telemetry
    public func stopRecording() async throws -> RecordingResult {
        guard let session = currentSession else {
            throw TelemetryError.notRecording
        }

        // Stop event monitoring on the main actor to match setup.
        await stopEventMonitoring()

        // Stop duration timer
        stopDurationTimer()

        // Close file handle
        try fileHandle?.close()
        fileHandle = nil

        // Mark session as ended
        session.markEnded(at: Date())

        // Build result
        let cursorFilePath = session.config.outputDirectory
            .appendingPathComponent("cursor.jsonl")

        let result = RecordingResult(
            sessionID: session.id,
            cursorFilePath: cursorFilePath,
            eventCount: session.eventCount,
            duration: session.duration,
            errorCounts: session.errorCounts
        )

        // Log error counts for diagnostics — catches writer pre-failure regressions
        if !session.errorCounts.isEmpty {
            let summary = session.errorCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            LogWarning(.capture, "Telemetry session error counts: \(summary)")
        }

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

    @MainActor
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
        if eventMonitor == nil {
            LogWarning(.capture, "Global mouse event monitor returned nil; cursor telemetry may be unavailable")
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

    @MainActor
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
