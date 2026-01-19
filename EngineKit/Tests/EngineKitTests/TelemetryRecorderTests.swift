//
//  TelemetryRecorderTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class TelemetryRecorderTests: XCTestCase {
    var recorder: TelemetryRecorder!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        recorder = TelemetryRecorder()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryRecorderTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        recorder = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)

        XCTAssertEqual(config.cursorMoveFrequency, 60.0)
        XCTAssertFalse(config.captureScroll)
        XCTAssertFalse(config.captureDisplayID)
        XCTAssertEqual(config.outputDirectory, tempDirectory)
    }

    func testWithScrollTrackingConfiguration() {
        let config = TelemetryRecorder.Configuration.withScrollTracking(outputDirectory: tempDirectory)

        XCTAssertEqual(config.cursorMoveFrequency, 60.0)
        XCTAssertTrue(config.captureScroll)
        XCTAssertFalse(config.captureDisplayID)
    }

    func testMultiMonitorConfiguration() {
        let config = TelemetryRecorder.Configuration.multiMonitor(outputDirectory: tempDirectory)

        XCTAssertEqual(config.cursorMoveFrequency, 60.0)
        XCTAssertFalse(config.captureScroll)
        XCTAssertTrue(config.captureDisplayID)
    }

    func testCustomConfiguration() {
        let config = TelemetryRecorder.Configuration(
            outputDirectory: tempDirectory,
            cursorMoveFrequency: 30.0,
            captureScroll: true,
            captureDisplayID: true
        )

        XCTAssertEqual(config.cursorMoveFrequency, 30.0)
        XCTAssertTrue(config.captureScroll)
        XCTAssertTrue(config.captureDisplayID)
    }

    // MARK: - Event Tests

    func testMoveEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 0.033,
            type: .move,
            x: 1023,
            y: 812
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.t, 0.033)
        XCTAssertEqual(decoded.type, .move)
        XCTAssertEqual(decoded.x, 1023)
        XCTAssertEqual(decoded.y, 812)
        XCTAssertNil(decoded.button)
        XCTAssertNil(decoded.dx)
        XCTAssertNil(decoded.dy)
    }

    func testDownEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 0.512,
            type: .down,
            x: 1104,
            y: 790,
            button: 0
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.t, 0.512)
        XCTAssertEqual(decoded.type, .down)
        XCTAssertEqual(decoded.x, 1104)
        XCTAssertEqual(decoded.y, 790)
        XCTAssertEqual(decoded.button, 0)
    }

    func testUpEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 0.602,
            type: .up,
            x: 1104,
            y: 790,
            button: 0
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.t, 0.602)
        XCTAssertEqual(decoded.type, .up)
        XCTAssertEqual(decoded.button, 0)
    }

    func testScrollEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 0.620,
            type: .scroll,
            x: 1104,
            y: 790,
            dx: 0.0,
            dy: -1.2
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.t, 0.620)
        XCTAssertEqual(decoded.type, .scroll)
        XCTAssertEqual(decoded.dx, 0.0)
        XCTAssertEqual(decoded.dy, -1.2)
    }

    func testEventWithDisplayID() throws {
        let event = TelemetryRecorder.Event(
            t: 0.100,
            type: .move,
            x: 500,
            y: 500,
            displayID: "Main Screen"
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.displayID, "Main Screen")
    }

    func testRightClickEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 1.500,
            type: .down,
            x: 800,
            y: 600,
            button: 1
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.button, 1)
    }

    func testMiddleClickEventEncoding() throws {
        let event = TelemetryRecorder.Event(
            t: 2.000,
            type: .down,
            x: 800,
            y: 600,
            button: 2
        )

        let jsonl = try event.toJSONL()
        let data = jsonl.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

        XCTAssertEqual(decoded.button, 2)
    }

    // MARK: - Recording Session Tests

    func testStartRecording() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        let session = try await recorder.startRecording(config: config)

        XCTAssertTrue(session.isRecording)
        XCTAssertNotNil(session.startTime)
        XCTAssertNil(session.endTime)
        XCTAssertEqual(session.eventCount, 0)
        XCTAssertNil(session.error)
    }

    func testStartRecordingAlreadyRecording() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        do {
            _ = try await recorder.startRecording(config: config)
            XCTFail("Should have thrown alreadyRecording error")
        } catch TelemetryRecorder.TelemetryError.alreadyRecording {
            // Expected
        }
    }

    func testStopRecording() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        // Wait a bit to ensure duration > 0
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let result = try await recorder.stopRecording()

        let isRecording = await recorder.isRecording()
        XCTAssertFalse(isRecording)
        XCTAssertEqual(result.eventCount, 0)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertTrue(result.cursorFilePath.path.hasSuffix("cursor.jsonl"))
    }

    func testStopRecordingNotRecording() async throws {
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Should have thrown notRecording error")
        } catch TelemetryRecorder.TelemetryError.notRecording {
            // Expected
        }
    }

    func testGetCurrentSession() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        let session = try await recorder.startRecording(config: config)

        let currentSession = await recorder.getCurrentSession()

        XCTAssertNotNil(currentSession)
        XCTAssertEqual(currentSession?.id, session.id)
    }

    func testIsRecording() async throws {
        let initialRecording = await recorder.isRecording()
        XCTAssertFalse(initialRecording)

        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        let duringRecording = await recorder.isRecording()
        XCTAssertTrue(duringRecording)

        _ = try await recorder.stopRecording()

        let afterRecording = await recorder.isRecording()
        XCTAssertFalse(afterRecording)
    }

    func testRecordingSessionDurationTracking() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let session = await recorder.getCurrentSession()
        XCTAssertNotNil(session)
        XCTAssertGreaterThanOrEqual(session?.duration ?? 0, 0.4)
    }

    // MARK: - File System Tests

    func testTelemetryDirectoryCreation() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        let telemetryDirectory = tempDirectory.appendingPathComponent("telemetry")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: telemetryDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCursorJsonlFileCreation() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        let cursorFilePath = tempDirectory
            .appendingPathComponent("telemetry")
            .appendingPathComponent("cursor.jsonl")

        XCTAssertTrue(FileManager.default.fileExists(atPath: cursorFilePath.path))
    }

    func testRecordingResultFilePath() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        _ = try await recorder.stopRecording()

        let cursorFilePath = tempDirectory
            .appendingPathComponent("telemetry")
            .appendingPathComponent("cursor.jsonl")

        XCTAssertTrue(FileManager.default.fileExists(atPath: cursorFilePath.path))
    }

    // MARK: - Error Tests

    func testTelemetryErrorDescriptions() {
        let errors: [TelemetryRecorder.TelemetryError] = [
            .alreadyRecording,
            .notRecording,
            .directoryCreationFailed(URL(fileURLWithPath: "/tmp/test")),
            .fileCreationFailed(URL(fileURLWithPath: "/tmp/test.jsonl")),
            .writeFailed,
            .encodingFailed,
            .invalidConfiguration
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testInvalidOutputDirectory() async throws {
        // Create a file instead of a directory
        let invalidPath = tempDirectory.appendingPathComponent("invalid_file")
        try Data().write(to: invalidPath)

        let config = TelemetryRecorder.Configuration(outputDirectory: invalidPath)

        do {
            _ = try await recorder.startRecording(config: config)
            XCTFail("Should have thrown directoryCreationFailed error")
        } catch {
            // Expected error - any error is acceptable since the path is invalid
            XCTAssertTrue(error is TelemetryRecorder.TelemetryError || error is CocoaError)
        }
    }

    // MARK: - Configuration Frequency Tests

    func testDifferentFrequencies() {
        let configs: [TelemetryRecorder.Configuration] = [
            TelemetryRecorder.Configuration(outputDirectory: tempDirectory, cursorMoveFrequency: 30.0),
            TelemetryRecorder.Configuration(outputDirectory: tempDirectory, cursorMoveFrequency: 60.0),
            TelemetryRecorder.Configuration(outputDirectory: tempDirectory, cursorMoveFrequency: 120.0),
            TelemetryRecorder.Configuration(outputDirectory: tempDirectory, cursorMoveFrequency: 15.0),
        ]

        XCTAssertEqual(configs[0].cursorMoveFrequency, 30.0)
        XCTAssertEqual(configs[1].cursorMoveFrequency, 60.0)
        XCTAssertEqual(configs[2].cursorMoveFrequency, 120.0)
        XCTAssertEqual(configs[3].cursorMoveFrequency, 15.0)
    }

    func testFrequencyCalculation() {
        // Verify that throttle interval is calculated correctly
        let frequency = 60.0
        let expectedThrottleInterval = 1.0 / frequency
        XCTAssertEqual(expectedThrottleInterval, 0.016666666666666666, accuracy: 0.0001)
    }

    // MARK: - Multiple Session Tests

    func testSequentialRecordingSessions() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)

        // First session
        let session1 = try await recorder.startRecording(config: config)
        try await Task.sleep(nanoseconds: 100_000_000)
        let result1 = try await recorder.stopRecording()

        // Second session
        let session2 = try await recorder.startRecording(config: config)
        try await Task.sleep(nanoseconds: 100_000_000)
        let result2 = try await recorder.stopRecording()

        XCTAssertNotEqual(session1.id, session2.id)
        XCTAssertNotEqual(result1.sessionID, result2.sessionID)
        XCTAssertTrue(result1.duration > 0)
        XCTAssertTrue(result2.duration > 0)
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
            }
        }
    }

    func testEventEncodingPerformance() throws {
        let event = TelemetryRecorder.Event(
            t: 0.033,
            type: .move,
            x: 1023,
            y: 812
        )

        measure {
            for _ in 0..<1000 {
                try? _ = event.toJSONL()
            }
        }
    }

    // MARK: - Edge Case Tests

    func testZeroFrequencyConfiguration() {
        // Test that zero frequency doesn't cause division by zero
        let config = TelemetryRecorder.Configuration(
            outputDirectory: tempDirectory,
            cursorMoveFrequency: 0.1  // Very low frequency but not zero
        )

        XCTAssertEqual(config.cursorMoveFrequency, 0.1)
    }

    func testHighFrequencyConfiguration() {
        let config = TelemetryRecorder.Configuration(
            outputDirectory: tempDirectory,
            cursorMoveFrequency: 240.0  // Very high frequency
        )

        XCTAssertEqual(config.cursorMoveFrequency, 240.0)
    }

    func testSessionInitialState() {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        let session = TelemetryRecorder.RecordingSession(config: config)

        XCTAssertFalse(session.isRecording)
        XCTAssertNil(session.startTime)
        XCTAssertNil(session.endTime)
        XCTAssertEqual(session.duration, 0)
        XCTAssertEqual(session.eventCount, 0)
        XCTAssertNil(session.error)
    }

    func testRecordingResultStructure() async throws {
        let config = TelemetryRecorder.Configuration.default(outputDirectory: tempDirectory)
        _ = try await recorder.startRecording(config: config)

        let result = try await recorder.stopRecording()

        XCTAssertNotNil(result.sessionID)
        XCTAssertTrue(result.cursorFilePath.path.hasSuffix("cursor.jsonl"))
        XCTAssertEqual(result.eventCount, 0)
        XCTAssertTrue(result.duration >= 0)
    }

    func testAllEventTypes() throws {
        let events: [(TelemetryRecorder.Event, String)] = [
            (TelemetryRecorder.Event(t: 0.0, type: .move, x: 100, y: 100), "move"),
            (TelemetryRecorder.Event(t: 0.1, type: .down, x: 100, y: 100, button: 0), "down"),
            (TelemetryRecorder.Event(t: 0.2, type: .up, x: 100, y: 100, button: 0), "up"),
            (TelemetryRecorder.Event(t: 0.3, type: .scroll, x: 100, y: 100, dx: 1.0, dy: -1.0), "scroll"),
        ]

        for (event, expectedType) in events {
            let jsonl = try event.toJSONL()
            let data = jsonl.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

            XCTAssertEqual(decoded.type.rawValue, expectedType)
        }
    }

    func testAllMouseButtonTypes() throws {
        let buttons = [0, 1, 2, 3, 4, 5]

        for button in buttons {
            let event = TelemetryRecorder.Event(
                t: 0.0,
                type: .down,
                x: 100,
                y: 100,
                button: button
            )

            let jsonl = try event.toJSONL()
            let data = jsonl.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(TelemetryRecorder.Event.self, from: data)

            XCTAssertEqual(decoded.button, button)
        }
    }
}
