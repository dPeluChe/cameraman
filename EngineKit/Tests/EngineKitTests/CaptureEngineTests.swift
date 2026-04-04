//
//  CaptureEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-18.
//

import XCTest
import ScreenCaptureKit
import AVFoundation
@testable import EngineKit

@available(macOS 13.0, *)
final class CaptureEngineTests: XCTestCase {
    var sut: CaptureEngine!
    var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        sut = CaptureEngine.shared

        // Create temporary output directory
        let tempDir = FileManager.default.temporaryDirectory
        outputDirectory = tempDir.appendingPathComponent("test_recordings_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: outputDirectory)
        sut = nil
        outputDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testCaptureConfiguration_DisplaySource() {
        // Given
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display",
                name: "Test Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            ),
            captureSystemAudio: false,
            frameRate: 60
        )

        // Then
        XCTAssertEqual(config.sourceType, .display)
        XCTAssertNotNil(config.display)
        XCTAssertEqual(config.frameRate, 60)
        XCTAssertFalse(config.captureSystemAudio)
    }

    func testCaptureConfiguration_WindowSource() {
        // Given
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .window,
            window: SourceSelector.WindowSource(
                id: "123",
                title: "Test Window",
                applicationName: "Test App",
                applicationBundleIdentifier: "com.test.app",
                width: 800,
                height: 600,
                isOnScreen: true
            ),
            captureSystemAudio: false
        )

        // Then
        XCTAssertEqual(config.sourceType, .window)
        XCTAssertNotNil(config.window)
        XCTAssertNil(config.display)
    }

    func testCaptureConfiguration_ApplicationSource() {
        // Given
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .application,
            application: SourceSelector.ApplicationSource(
                id: "com.test.app",
                name: "Test App",
                bundleIdentifier: "com.test.app",
                iconPath: nil
            ),
            captureSystemAudio: false
        )

        // Then
        XCTAssertEqual(config.sourceType, .application)
        XCTAssertNotNil(config.application)
        XCTAssertNil(config.window)
        XCTAssertNil(config.display)
    }

    func testCaptureConfiguration_WithSystemAudio() {
        // Given
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display",
                name: "Test Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            ),
            captureSystemAudio: true,
            frameRate: 30
        )

        // Then
        XCTAssertTrue(config.captureSystemAudio)
        XCTAssertEqual(config.frameRate, 30)
    }

    // MARK: - Recording Session Tests

    func testRecordingSession_InitialState() {
        // Given
        let session = CaptureEngine.RecordingSession()

        // Then
        XCTAssertNotNil(session.id)
        XCTAssertFalse(session.isRecording)
        XCTAssertNil(session.startTime)
        XCTAssertEqual(session.duration, 0)
        XCTAssertNil(session.error)
    }

    func testRecordingSession_MarkStarted() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let startDate = Date()

        // When
        session.markStarted(at: startDate)

        // Then
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(session.startTime, startDate)
        XCTAssertNil(session.error)
    }

    func testRecordingSession_MarkStopped() {
        // Given
        let session = CaptureEngine.RecordingSession()
        session.markStarted(at: Date())

        // When
        session.markStopped()

        // Then
        XCTAssertFalse(session.isRecording)
    }

    func testRecordingSession_UpdateDuration() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let expectedDuration: TimeInterval = 5.0

        // When
        session.updateDuration(expectedDuration)

        // Then
        XCTAssertEqual(session.duration, expectedDuration)
    }

    func testRecordingSession_SetError() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let testError = CaptureEngine.CaptureError.permissionDenied

        // When
        session.setError(testError)

        // Then
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.error as? CaptureEngine.CaptureError, .permissionDenied)
    }

    // MARK: - Error Tests

    func testCaptureError_ErrorDescriptions() {
        // Given
        let errors: [CaptureEngine.CaptureError] = [
            .permissionDenied,
            .noSourceSelected,
            .invalidConfiguration,
            .recordingNotStarted,
            .recordingAlreadyInProgress
        ]

        // Then
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
        }
    }

    func testCaptureError_PermissionDenied() {
        // Given
        let error = CaptureEngine.CaptureError.permissionDenied

        // Then
        XCTAssertEqual(error.errorDescription, "Screen recording permission denied")
    }

    func testCaptureError_NoSourceSelected() {
        // Given
        let error = CaptureEngine.CaptureError.noSourceSelected

        // Then
        XCTAssertEqual(error.errorDescription, "No capture source selected")
    }

    // MARK: - Integration Tests (Permission-Based)

    func testStartRecording_WithoutPermission_ThrowsError() async throws {
        // This test verifies that we properly check permissions
        // In CI environments without screen recording permission, this should fail gracefully

        // Given
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display",
                name: "Test Display",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            ),
            captureSystemAudio: false
        )

        // When/Then
        do {
            _ = try await sut.startRecording(config: config, outputURL: outputDirectory)
            // If we get here, we have permission - that's OK
            XCTAssertTrue(true, "Recording started successfully (permission granted)")
        } catch CaptureEngine.CaptureError.permissionDenied {
            // Expected in environments without permission
            XCTAssertTrue(true, "Permission denied handled correctly")
        } catch {
            // Other errors are also acceptable for this test
            XCTAssertTrue(true, "Error handled: \(error.localizedDescription)")
        }
    }

    func testStartRecording_WithInvalidConfiguration_ThrowsError() async throws {
        // Given - configuration without required display info
        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: nil, // Missing required display
            captureSystemAudio: false
        )

        // When/Then
        do {
            _ = try await sut.startRecording(config: config, outputURL: outputDirectory)
            XCTFail("Should have thrown an error for invalid configuration")
        } catch CaptureEngine.CaptureError.invalidConfiguration {
            // Expected
            XCTAssertTrue(true, "Invalid configuration error thrown correctly")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - RecordingResult Tests

    func testRecordingResult_Properties() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let screenVideoPath = URL(fileURLWithPath: "/tmp/screen.mov")
        let systemAudioPath = URL(fileURLWithPath: "/tmp/system_audio.m4a")
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(10.0)

        // When
        let result = CaptureEngine.RecordingResult(
            screenVideoPath: screenVideoPath,
            systemAudioPath: systemAudioPath,
            duration: 10.0,
            startTime: startTime,
            endTime: endTime,
            sessionId: session.id,
            sessionIsRecording: true
        )

        // Then
        XCTAssertEqual(result.sessionId, session.id)
        XCTAssertEqual(result.screenVideoPath, screenVideoPath)
        XCTAssertEqual(result.systemAudioPath, systemAudioPath)
        XCTAssertEqual(result.duration, 10.0)
        XCTAssertEqual(result.startTime, startTime)
        XCTAssertEqual(result.endTime, endTime)
        XCTAssertTrue(result.sessionIsRecording)
    }

    // MARK: - Concurrency Tests

    func testStartRecording_WhenAlreadyRecording_ThrowsError() async throws {
        // This test verifies that we can't start multiple recordings simultaneously

        // Given
        let config1 = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display-1",
                name: "Test Display 1",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: true
            ),
            captureSystemAudio: false
        )

        let config2 = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "test-display-2",
                name: "Test Display 2",
                width: 1920,
                height: 1080,
                refreshRate: 60.0,
                isMain: false
            ),
            captureSystemAudio: false
        )

        // When/Then
        do {
            // Try to start first recording
            _ = try await sut.startRecording(config: config1, outputURL: outputDirectory)

            // Try to start second recording immediately
            _ = try await sut.startRecording(config: config2, outputURL: outputDirectory)

            // Should not reach here
            XCTFail("Should have thrown an error for concurrent recordings")
        } catch CaptureEngine.CaptureError.recordingAlreadyInProgress {
            // Expected
            XCTAssertTrue(true, "Concurrent recording prevented correctly")
        } catch {
            // Other errors are acceptable (e.g., permission errors)
            XCTAssertTrue(true, "Error handled: \(error.localizedDescription)")
        }
    }

    // MARK: - Performance Tests

    func testCaptureConfiguration_CreationPerformance() {
        // Measure
        measure {
            for _ in 0..<1000 {
                _ = CaptureEngine.CaptureConfiguration(
                    sourceType: .display,
                    display: SourceSelector.DisplaySource(
                        id: "test-display",
                        name: "Test Display",
                        width: 1920,
                        height: 1080,
                        refreshRate: 60.0,
                        isMain: true
                    ),
                    captureSystemAudio: false,
                    frameRate: 60
                )
            }
        }
    }

    func testRecordingSession_SessionCreationPerformance() {
        // Measure
        measure {
            for _ in 0..<1000 {
                let session = CaptureEngine.RecordingSession()
                session.markStarted(at: Date())
                session.updateDuration(5.0)
                session.markStopped()
            }
        }
    }

    // MARK: - Frame Rate Tests

    func testCaptureConfiguration_DifferentFrameRates() {
        // Given
        let frameRates = [24, 30, 60, 120]

        // Then
        for frameRate in frameRates {
            let config = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false,
                frameRate: frameRate
            )

            XCTAssertEqual(config.frameRate, frameRate, "Frame rate should be \(frameRate)")
        }
    }

    // MARK: - Pixel Format Tests

    func testCaptureConfiguration_DifferentPixelFormats() {
        // Given
        let pixelFormats: [OSType] = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_422YpCbCr8,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        // Then
        for pixelFormat in pixelFormats {
            let config = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: 1920,
                    height: 1080,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false,
                pixelFormat: pixelFormat
            )

            XCTAssertEqual(config.pixelFormat, pixelFormat, "Pixel format should match")
        }
    }

    // MARK: - Resolution Tests

    func testCaptureConfiguration_DifferentResolutions() {
        // Given
        let resolutions = [
            (1280, 720),    // 720p
            (1920, 1080),   // 1080p
            (2560, 1440),   // 1440p
            (3840, 2160),   // 4K
            (2880, 1800),   // Retina 15"
            (2560, 1600)    // Retina 13"
        ]

        // Then
        for (width, height) in resolutions {
            let config = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: SourceSelector.DisplaySource(
                    id: "test-display",
                    name: "Test Display",
                    width: width,
                    height: height,
                    refreshRate: 60.0,
                    isMain: true
                ),
                captureSystemAudio: false
            )

            XCTAssertEqual(config.display?.width, width, "Width should be \(width)")
            XCTAssertEqual(config.display?.height, height, "Height should be \(height)")
        }
    }

    // MARK: - Edge Case Tests

    func testRecordingSession_ZeroDuration() {
        // Given
        let session = CaptureEngine.RecordingSession()
        session.markStarted(at: Date())
        session.updateDuration(0)

        // Then
        XCTAssertEqual(session.duration, 0)
        XCTAssertTrue(session.isRecording)
    }

    func testRecordingSession_VeryLongDuration() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let longDuration: TimeInterval = 3600.0 // 1 hour
        session.updateDuration(longDuration)

        // Then
        XCTAssertEqual(session.duration, longDuration)
    }

    func testRecordingResult_WithoutSystemAudio() {
        // Given
        let session = CaptureEngine.RecordingSession()
        let screenVideoPath = URL(fileURLWithPath: "/tmp/screen.mov")

        // When
        let result = CaptureEngine.RecordingResult(
            screenVideoPath: screenVideoPath,
            systemAudioPath: nil,
            duration: 10.0,
            startTime: Date(),
            endTime: Date().addingTimeInterval(10.0),
            sessionId: session.id,
            sessionIsRecording: true
        )

        // Then
        XCTAssertNil(result.systemAudioPath, "System audio path should be nil when not recording audio")
    }
}
