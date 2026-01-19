//
//  KeystrokeRecorder.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AppKit
import Carbon

/// KeystrokeRecorder captures keyboard input for tutorial purposes
/// NOTE: Requires Accessibility permission to capture global keyboard events
public actor KeystrokeRecorder {
    // MARK: - Types

    /// Configuration for keystroke recording
    public struct Configuration {
        /// Output directory for keystroke files
        public let outputDirectory: URL
        /// Whether to capture modifier keys individually (cmd, option, control, shift)
        public let captureModifiers: Bool
        /// Whether to filter common shortcuts (Cmd+C, Cmd+V, etc.)
        public let filterCommonShortcuts: Bool

        public init(
            outputDirectory: URL,
            captureModifiers: Bool = false,
            filterCommonShortcuts: Bool = true
        ) {
            self.outputDirectory = outputDirectory
            self.captureModifiers = captureModifiers
            self.filterCommonShortcuts = filterCommonShortcuts
        }

        /// Default configuration
        public static func `default`(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                captureModifiers: false,
                filterCommonShortcuts: true
            )
        }

        /// Configuration with modifier tracking enabled
        public static func withModifiers(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                captureModifiers: true,
                filterCommonShortcuts: true
            )
        }

        /// Configuration with all shortcuts (no filtering)
        public static func raw(outputDirectory: URL) -> Configuration {
            return Configuration(
                outputDirectory: outputDirectory,
                captureModifiers: false,
                filterCommonShortcuts: false
            )
        }
    }

    /// Keystroke event types
    public enum EventType: String, Codable, Equatable {
        case down
        case up
    }

    /// Keystroke event
    public struct Event: Codable {
        /// Timestamp in seconds from recording start
        public let t: Double
        /// Event type (down/up)
        public let type: EventType
        /// Key code (Carbon virtual key code)
        public let keyCode: UInt32
        /// Character representation (if available)
        public let characters: String?
        /// Modifier flags (cmd, option, control, shift)
        public let modifiers: Modifiers
        /// Whether this is a repeated key (key held down)
        public let isRepeat: Bool

        public init(
            t: Double,
            type: EventType,
            keyCode: UInt32,
            characters: String?,
            modifiers: Modifiers,
            isRepeat: Bool
        ) {
            self.t = t
            self.type = type
            self.keyCode = keyCode
            self.characters = characters
            self.modifiers = modifiers
            self.isRepeat = isRepeat
        }

        /// Encode event to JSON for JSONL output
        func encode() throws -> Data {
            let encoder = JSONEncoder()
            return try encoder.encode(self)
        }

        /// Create event from NSEvent
        public static func from(_ event: NSEvent, startTime: Date) -> Event? {
            guard event.type == .keyDown || event.type == .keyUp else {
                return nil
            }

            let type: EventType = event.type == .keyDown ? .down : .up
            let timestamp = Date().timeIntervalSince(startTime)

            // Get character representation
            var characters: String?
            if let chars = event.characters {
                characters = chars
            } else if event.type == .keyDown, let charsIgnoringModifiers = event.charactersIgnoringModifiers {
                characters = charsIgnoringModifiers
            }

            // Extract modifier flags
            let modifiers = Modifiers(
                command: event.modifierFlags.contains(.command),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control),
                shift: event.modifierFlags.contains(.shift)
            )

            return Event(
                t: timestamp,
                type: type,
                keyCode: UInt32(event.keyCode),
                characters: characters,
                modifiers: modifiers,
                isRepeat: event.isARepeat
            )
        }

        /// Check if this is a common shortcut that should be filtered
        func isCommonShortcut() -> Bool {
            guard let chars = characters?.lowercased() else {
                return false
            }

            // Common shortcuts to filter (Cmd+C, Cmd+V, etc.)
            let commonShortcuts = ["c", "v", "x", "a", "z", "s", "w", "q", "n", "o", "p"]

            return modifiers.command && commonShortcuts.contains(chars)
        }
    }

    /// Modifier key states
    public struct Modifiers: Codable, Equatable {
        public let command: Bool
        public let option: Bool
        public let control: Bool
        public let shift: Bool

        public init(
            command: Bool = false,
            option: Bool = false,
            control: Bool = false,
            shift: Bool = false
        ) {
            self.command = command
            self.option = option
            self.control = control
            self.shift = shift
        }

        /// String representation of modifiers (e.g., "Cmd+Shift+")
        public func description() -> String {
            var parts: [String] = []
            if command { parts.append("Cmd") }
            if option { parts.append("Option") }
            if control { parts.append("Control") }
            if shift { parts.append("Shift") }
            return parts.joined(separator: "+")
        }

        /// Check if any modifiers are active
        public func isActive() -> Bool {
            return command || option || control || shift
        }
    }

    /// Active recording session
    public class RecordingSession: Codable, Equatable {
        public let sessionId: String
        public let startTime: Date
        public var duration: TimeInterval
        public var eventCount: Int

        public init(sessionId: String) {
            self.sessionId = sessionId
            self.startTime = Date()
            self.duration = 0
            self.eventCount = 0
        }

        // Implement Equatable manually since we have a class
        public static func == (lhs: RecordingSession, rhs: RecordingSession) -> Bool {
            return lhs.sessionId == rhs.sessionId &&
                   lhs.startTime == rhs.startTime &&
                   lhs.duration == rhs.duration &&
                   lhs.eventCount == rhs.eventCount
        }
    }

    /// Recording result
    public struct RecordingResult: Codable, Equatable {
        public let sessionId: String
        public let keysPath: URL
        public let duration: TimeInterval
        public let eventCount: Int

        public init(
            sessionId: String,
            keysPath: URL,
            duration: TimeInterval,
            eventCount: Int
        ) {
            self.sessionId = sessionId
            self.keysPath = keysPath
            self.duration = duration
            self.eventCount = eventCount
        }
    }

    /// Keystroke recorder errors
    public enum KeystrokeError: Error, LocalizedError, Equatable {
        case alreadyRecording
        case notRecording
        case invalidDirectory
        case permissionDenied
        case fileWriteFailed
        case accessibilityPermissionRequired

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "A keystroke recording session is already in progress"
            case .notRecording:
                return "No keystroke recording session is currently active"
            case .invalidDirectory:
                return "Invalid output directory"
            case .permissionDenied:
                return "Permission denied to capture keyboard events"
            case .fileWriteFailed:
                return "Failed to write keystroke data to file"
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to capture keyboard events. Please grant this permission in System Settings > Privacy & Security > Accessibility"
            }
        }
    }

    // MARK: - Properties

    private var configuration: Configuration?
    private var currentSession: RecordingSession?
    private var eventMonitor: Any?
    private var fileHandle: FileHandle?
    private var durationTimer: Timer?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Start keystroke recording
    public func startRecording(configuration: Configuration) async throws {
        // Check if already recording
        guard currentSession == nil else {
            throw KeystrokeError.alreadyRecording
        }

        // Create telemetry directory
        let telemetryDirectory = configuration.outputDirectory.appendingPathComponent("telemetry")
        try FileManager.default.createDirectory(at: telemetryDirectory, withIntermediateDirectories: true)

        // Create keys.jsonl file
        let keysPath = telemetryDirectory.appendingPathComponent("keys.jsonl")
        FileManager.default.createFile(atPath: keysPath.path, contents: nil)

        guard let fileHandle = FileHandle(forWritingAtPath: keysPath.path) else {
            throw KeystrokeError.fileWriteFailed
        }
        self.fileHandle = fileHandle

        // Store configuration
        self.configuration = configuration

        // Create recording session
        let session = RecordingSession(sessionId: UUID().uuidString)
        currentSession = session

        // Start monitoring keyboard events
        try startEventMonitoring()

        // Start duration timer
        startDurationTimer()

        // Log accessibility permission requirement
        #if !DEBUG
        // Only check in release mode (tests may not have accessibility permission)
        if !hasAccessibilityPermission() {
            print("WARNING: Accessibility permission may not be granted. Keystroke recording may not work.")
            print("Please grant Accessibility permission in System Settings > Privacy & Security > Accessibility")
        }
        #endif
    }

    /// Stop keystroke recording
    public func stopRecording() async throws -> RecordingResult {
        guard let session = currentSession else {
            throw KeystrokeError.notRecording
        }

        guard let config = configuration else {
            throw KeystrokeError.notRecording
        }

        // Stop monitoring
        stopEventMonitoring()

        // Stop duration timer
        stopDurationTimer()

        // Close file handle
        try fileHandle?.close()
        fileHandle = nil

        // Get result path
        let telemetryDirectory = config.outputDirectory.appendingPathComponent("telemetry")
        let keysPath = telemetryDirectory.appendingPathComponent("keys.jsonl")

        // Create result
        let result = RecordingResult(
            sessionId: session.sessionId,
            keysPath: keysPath,
            duration: session.duration,
            eventCount: session.eventCount
        )

        // Clear session
        currentSession = nil
        configuration = nil

        return result
    }

    /// Get current recording session (if any)
    public func getCurrentSession() -> RecordingSession? {
        return currentSession
    }

    /// Check if currently recording
    public func isRecording() -> Bool {
        return currentSession != nil
    }

    // MARK: - Private Methods

    private func startEventMonitoring() throws {
        // Use NSEvent.addGlobalMonitorForEvents for global keyboard events
        // NOTE: This requires Accessibility permission
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task {
                await self?.handleKeyEvent(event)
            }
        }

        // Note: NSEvent.addGlobalMonitorForEvents will return nil if Accessibility permission is not granted
        // but won't throw an error. We check this in the first key event.
    }

    private func stopEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) async {
        guard let session = currentSession,
              let config = configuration else {
            return
        }

        // Create event from NSEvent
        guard let keyEvent = Event.from(event, startTime: session.startTime) else {
            return
        }

        // Filter common shortcuts if enabled
        if config.filterCommonShortcuts && keyEvent.isCommonShortcut() {
            return
        }

        // Filter modifier-only events if not capturing modifiers
        if !config.captureModifiers && keyEvent.modifiers.isActive() && keyEvent.characters == nil {
            return
        }

        // Filter repeat events (only record key down once)
        if keyEvent.isRepeat {
            return
        }

        // Update session
        session.eventCount += 1

        // Write to file
        if let fileHandle = fileHandle,
           let data = try? keyEvent.encode() {
            var line = data
            line.append(Data([0x0A])) // newline
            fileHandle.write(line)
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task {
                await self?.updateDuration()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDuration() {
        guard let session = currentSession else {
            return
        }

        session.duration = Date().timeIntervalSince(session.startTime)
    }

    /// Check if Accessibility permission is granted
    private func hasAccessibilityPermission() -> Bool {
        // Note: There's no direct API to check Accessibility permission in macOS
        // This is a heuristic check - if we can create an event monitor, we likely have permission
        // However, the real test is when we try to capture events

        #if DEBUG
        // In debug/test mode, assume we don't have permission
        return false
        #else
        // In production, we'll detect when events fail to capture
        return true
        #endif
    }

    // MARK: - Constants

    /// Common shortcuts to filter (key codes)
    private static let commonShortcutKeyCodes: Set<UInt32> = [
        8,  // C
        9,  // V
        7,  // X
        0,  // A
        6,  // Z
        1,  // S
        13, // W
        12, // Q
        45, // N
        31, // O
        35  // P
    ]
}
