//
//  KeystrokeRecorderTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class KeystrokeRecorderTests: XCTestCase {

    var tempDirectory: URL!
    var recorder: KeystrokeRecorder!

    override func setUp() {
        super.setUp()
        // Create temporary directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeystrokeRecorderTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        recorder = KeystrokeRecorder()
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)

        XCTAssertEqual(config.outputDirectory, tempDirectory)
        XCTAssertFalse(config.captureModifiers)
        XCTAssertTrue(config.filterCommonShortcuts)
    }

    func testWithModifiersConfiguration() {
        let config = KeystrokeRecorder.Configuration.withModifiers(outputDirectory: tempDirectory)

        XCTAssertEqual(config.outputDirectory, tempDirectory)
        XCTAssertTrue(config.captureModifiers)
        XCTAssertTrue(config.filterCommonShortcuts)
    }

    func testRawConfiguration() {
        let config = KeystrokeRecorder.Configuration.raw(outputDirectory: tempDirectory)

        XCTAssertEqual(config.outputDirectory, tempDirectory)
        XCTAssertFalse(config.captureModifiers)
        XCTAssertFalse(config.filterCommonShortcuts)
    }

    func testCustomConfiguration() {
        let config = KeystrokeRecorder.Configuration(
            outputDirectory: tempDirectory,
            captureModifiers: true,
            filterCommonShortcuts: false
        )

        XCTAssertEqual(config.outputDirectory, tempDirectory)
        XCTAssertTrue(config.captureModifiers)
        XCTAssertFalse(config.filterCommonShortcuts)
    }

    // MARK: - Event Tests

    func testEventEncoding() throws {
        let modifiers = KeystrokeRecorder.Modifiers(command: true, option: false, control: false, shift: false)
        let event = KeystrokeRecorder.Event(
            t: 1.234,
            type: .down,
            keyCode: 8, // C key
            characters: "c",
            modifiers: modifiers,
            isRepeat: false
        )

        let data = try event.encode()
        XCTAssertFalse(data.isEmpty)

        // Verify it's valid JSON
        let json = try JSONDecoder().decode(KeystrokeRecorder.Event.self, from: data)
        XCTAssertEqual(json.t, 1.234)
        XCTAssertEqual(json.type, KeystrokeRecorder.EventType.down)
        XCTAssertEqual(json.keyCode, 8)
        XCTAssertEqual(json.characters, "c")
        XCTAssertTrue(json.modifiers.command)
    }

    func testModifiersDescription() {
        let cmd = KeystrokeRecorder.Modifiers(command: true)
        XCTAssertEqual(cmd.description(), "Cmd")

        let cmdShift = KeystrokeRecorder.Modifiers(command: true, shift: true)
        XCTAssertEqual(cmdShift.description(), "Cmd+Shift")

        let all = KeystrokeRecorder.Modifiers(command: true, option: true, control: true, shift: true)
        XCTAssertTrue(all.description().contains("Cmd"))
        XCTAssertTrue(all.description().contains("Option"))
        XCTAssertTrue(all.description().contains("Control"))
        XCTAssertTrue(all.description().contains("Shift"))
    }

    func testModifiersIsActive() {
        let none = KeystrokeRecorder.Modifiers()
        XCTAssertFalse(none.isActive())

        let cmd = KeystrokeRecorder.Modifiers(command: true)
        XCTAssertTrue(cmd.isActive())

        let shift = KeystrokeRecorder.Modifiers(shift: true)
        XCTAssertTrue(shift.isActive())
    }

    func testEventIsCommonShortcut() {
        // Cmd+C (copy) should be common
        var modifiers = KeystrokeRecorder.Modifiers(command: true)
        var event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 8,
            characters: "c",
            modifiers: modifiers,
            isRepeat: false
        )
        XCTAssertTrue(event.isCommonShortcut())

        // Cmd+V (paste) should be common
        event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 9,
            characters: "v",
            modifiers: modifiers,
            isRepeat: false
        )
        XCTAssertTrue(event.isCommonShortcut())

        // X without Cmd should not be common
        modifiers = KeystrokeRecorder.Modifiers()
        event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 7,
            characters: "x",
            modifiers: modifiers,
            isRepeat: false
        )
        XCTAssertFalse(event.isCommonShortcut())

        // A with Option should not be common
        modifiers = KeystrokeRecorder.Modifiers(option: true)
        event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 0,
            characters: "a",
            modifiers: modifiers,
            isRepeat: false
        )
        XCTAssertFalse(event.isCommonShortcut())
    }

    // MARK: - RecordingSession Tests

    func testRecordingSessionCreation() {
        let session = KeystrokeRecorder.RecordingSession(sessionId: "test-id")

        XCTAssertEqual(session.sessionId, "test-id")
        XCTAssertEqual(session.duration, 0)
        XCTAssertEqual(session.eventCount, 0)
    }

    func testRecordingSessionUpdate() {
        let session = KeystrokeRecorder.RecordingSession(sessionId: "test-id")

        // Simulate event count update
        session.eventCount = 10
        XCTAssertEqual(session.eventCount, 10)

        // Simulate duration update
        session.duration = 5.0
        XCTAssertEqual(session.duration, 5.0)
    }

    // MARK: - RecordingResult Tests

    func testRecordingResultCreation() {
        let keysPath = tempDirectory.appendingPathComponent("telemetry/keys.jsonl")
        let result = KeystrokeRecorder.RecordingResult(
            sessionId: "test-session",
            keysPath: keysPath,
            duration: 10.5,
            eventCount: 42
        )

        XCTAssertEqual(result.sessionId, "test-session")
        XCTAssertEqual(result.keysPath, keysPath)
        XCTAssertEqual(result.duration, 10.5)
        XCTAssertEqual(result.eventCount, 42)
    }

    // MARK: - Recorder Lifecycle Tests

    func testStartRecordingCreatesDirectoryAndFile() async throws {
        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)

        try await recorder.startRecording(configuration: config)

        // Verify telemetry directory was created
        let telemetryDirectory = tempDirectory.appendingPathComponent("telemetry")
        XCTAssertTrue(FileManager.default.fileExists(atPath: telemetryDirectory.path))

        // Verify keys.jsonl file was created
        let keysPath = telemetryDirectory.appendingPathComponent("keys.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keysPath.path))

        // Clean up
        _ = try await recorder.stopRecording()
    }

    func testStartRecordingWhenAlreadyRecordingFails() async throws {
        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)

        try await recorder.startRecording(configuration: config)

        // Try to start recording again
        do {
            try await recorder.startRecording(configuration: config)
            XCTFail("Should have thrown KeystrokeError.alreadyRecording")
        } catch KeystrokeRecorder.KeystrokeError.alreadyRecording {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Clean up
        _ = try await recorder.stopRecording()
    }

    func testStopRecordingWhenNotRecordingFails() async {
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Should have thrown KeystrokeError.notRecording")
        } catch KeystrokeRecorder.KeystrokeError.notRecording {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testStopRecordingReturnsResult() async throws {
        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)

        try await recorder.startRecording(configuration: config)

        // Wait a bit
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let result = try await recorder.stopRecording()

        XCTAssertNotNil(result.sessionId)
        XCTAssertEqual(result.keysPath, tempDirectory.appendingPathComponent("telemetry/keys.jsonl"))
        XCTAssertGreaterThanOrEqual(result.duration, 0)
        XCTAssertEqual(result.eventCount, 0) // No events in test
    }

    func testIsRecording() async throws {
        let isRecordingBefore = await recorder.isRecording()
        XCTAssertFalse(isRecordingBefore)

        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)
        try await recorder.startRecording(configuration: config)

        let isRecordingDuring = await recorder.isRecording()
        XCTAssertTrue(isRecordingDuring)

        _ = try await recorder.stopRecording()

        let isRecordingAfter = await recorder.isRecording()
        XCTAssertFalse(isRecordingAfter)
    }

    func testGetCurrentSession() async throws {
        let sessionBefore = await recorder.getCurrentSession()
        XCTAssertNil(sessionBefore)

        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)
        try await recorder.startRecording(configuration: config)

        let session = await recorder.getCurrentSession()
        XCTAssertNotNil(session)
        XCTAssertNotNil(session?.sessionId)
        XCTAssertEqual(session?.eventCount, 0)

        _ = try await recorder.stopRecording()

        let sessionAfter = await recorder.getCurrentSession()
        XCTAssertNil(sessionAfter)
    }

    // MARK: - Sequential Recording Tests

    func testSequentialRecordingSessions() async throws {
        let config = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)

        // First session
        try await recorder.startRecording(configuration: config)
        let session1 = await recorder.getCurrentSession()
        XCTAssertNotNil(session1)

        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let result1 = try await recorder.stopRecording()
        XCTAssertGreaterThanOrEqual(result1.duration, 0)

        // Second session
        try await recorder.startRecording(configuration: config)
        let session2 = await recorder.getCurrentSession()
        XCTAssertNotNil(session2)

        // Verify session IDs are different
        XCTAssertNotEqual(session1?.sessionId, session2?.sessionId)

        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let result2 = try await recorder.stopRecording()
        XCTAssertGreaterThanOrEqual(result2.duration, 0)

        // Verify results are different
        XCTAssertNotEqual(result1.sessionId, result2.sessionId)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.alreadyRecording.errorDescription,
            "A keystroke recording session is already in progress"
        )

        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.notRecording.errorDescription,
            "No keystroke recording session is currently active"
        )

        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.invalidDirectory.errorDescription,
            "Invalid output directory"
        )

        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.permissionDenied.errorDescription,
            "Permission denied to capture keyboard events"
        )

        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.fileWriteFailed.errorDescription,
            "Failed to write keystroke data to file"
        )

        XCTAssertEqual(
            KeystrokeRecorder.KeystrokeError.accessibilityPermissionRequired.errorDescription,
            "Accessibility permission is required to capture keyboard events. Please grant this permission in System Settings > Privacy & Security > Accessibility"
        )
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = KeystrokeRecorder.Configuration.default(outputDirectory: tempDirectory)
            }
        }
    }

    func testEventEncodingPerformance() throws {
        let event = KeystrokeRecorder.Event(
            t: 1.234,
            type: .down,
            keyCode: 8,
            characters: "c",
            modifiers: KeystrokeRecorder.Modifiers(command: true),
            isRepeat: false
        )

        measure {
            for _ in 0..<1000 {
                try? event.encode()
            }
        }
    }

    func testModifiersPerformance() {
        let modifiers = KeystrokeRecorder.Modifiers(command: true, shift: true)

        measure {
            for _ in 0..<10000 {
                _ = modifiers.isActive()
                _ = modifiers.description()
            }
        }
    }

    // MARK: - Edge Cases Tests

    func testEventWithNilCharacters() throws {
        let event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 55, // Command key
            characters: nil,
            modifiers: KeystrokeRecorder.Modifiers(command: true),
            isRepeat: false
        )

        let data = try event.encode()
        let json = try JSONDecoder().decode(KeystrokeRecorder.Event.self, from: data)

        XCTAssertNil(json.characters)
        XCTAssertEqual(json.keyCode, 55)
        XCTAssertTrue(json.modifiers.command)
    }

    func testEventWithRepeat() throws {
        let event = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 8,
            characters: "c",
            modifiers: KeystrokeRecorder.Modifiers(),
            isRepeat: true
        )

        XCTAssertTrue(event.isRepeat)
        XCTAssertEqual(event.type, .down)
    }

    func testAllEventTypes() throws {
        let modifiers = KeystrokeRecorder.Modifiers()

        // Key down event
        let downEvent = KeystrokeRecorder.Event(
            t: 0,
            type: .down,
            keyCode: 8,
            characters: "c",
            modifiers: modifiers,
            isRepeat: false
        )

        XCTAssertEqual(downEvent.type, .down)

        // Key up event
        let upEvent = KeystrokeRecorder.Event(
            t: 0.1,
            type: .up,
            keyCode: 8,
            characters: "c",
            modifiers: modifiers,
            isRepeat: false
        )

        XCTAssertEqual(upEvent.type, .up)
    }
}
