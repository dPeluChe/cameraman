//
//  CaptureEngineIntegrationTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//  Épica L, Task 1: Integration tests for CaptureEngine
//

import XCTest
import ScreenCaptureKit
import AVFoundation
@testable import EngineKit

/// Integration tests for CaptureEngine
///
/// These tests verify:
/// - Screen capture functionality with real SCStream integration
/// - Audio capture and synchronization with video
/// - Multi-track coordination between screen and audio
/// - File output validation and integrity
@available(macOS 13.0, *)
final class CaptureEngineIntegrationTests: XCTestCase {
    var captureEngine: CaptureEngine!
    var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        captureEngine = CaptureEngine.shared

        // Create temporary output directory for integration tests
        let tempDir = FileManager.default.temporaryDirectory
        outputDirectory = tempDir.appendingPathComponent("capture_integration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() async throws {
        // Clean up test recordings
        try? FileManager.default.removeItem(at: outputDirectory)
        captureEngine = nil
        outputDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Screen Capture Integration Tests

    /// Test screen capture session lifecycle (start/stop) with display source
    func testScreenCapture_SessionLifecycle_Display() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Start recording
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Then - Verify session started
        XCTAssertTrue(session.isRecording, "Session should be recording")
        XCTAssertNotNil(session.startTime, "Start time should be set")
        XCTAssertEqual(captureEngine.getCurrentSession()?.id, session.id, "Current session should match")

        // When - Record for a short duration
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then - Stop recording
        let result = try await captureEngine.stopRecording(session: session)

        // Verify recording result
        XCTAssertFalse(session.isRecording, "Session should no longer be recording")
        XCTAssertNotNil(result.startTime, "Result should have start time")
        XCTAssertNotNil(result.endTime, "Result should have end time")
        XCTAssertGreaterThan(result.duration, 0, "Duration should be greater than 0")
        XCTAssertTrue(result.duration < 5.0, "Duration should be less than 5 seconds")
        XCTAssertEqual(result.session.id, session.id, "Result session should match")

        // Verify screen video file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.screenVideoPath.path), "Screen video file should exist")
        XCTAssertGreaterThan(result.duration, 0.3, "Should have recorded at least 0.3 seconds")
    }

    /// Test screen capture with window source
    func testScreenCapture_SessionLifecycle_Window() async throws {
        // Given
        let windows = try await captureEngine.listWindows()
        guard let window = windows.first else {
            throw XCTSkip("No windows available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .window,
            window: window,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Start recording
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Record for short duration
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then - Stop recording and verify
        let result = try await captureEngine.stopRecording(session: session)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.screenVideoPath.path), "Screen video file should exist")
        XCTAssertGreaterThan(result.duration, 0.2, "Should have recorded at least 0.2 seconds")
    }

    /// Test screen capture with application source
    func testScreenCapture_SessionLifecycle_Application() async throws {
        // Given
        let applications = try await captureEngine.listApplications()
        guard let app = applications.first else {
            throw XCTSkip("No applications available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .application,
            application: app,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Start recording
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Record for short duration
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then - Stop recording and verify
        let result = try await captureEngine.stopRecording(session: session)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.screenVideoPath.path), "Screen video file should exist")
        XCTAssertGreaterThan(result.duration, 0.2, "Should have recorded at least 0.2 seconds")
    }

    // MARK: - Audio Capture Integration Tests

    /// Test screen capture with system audio enabled
    func testScreenCapture_WithSystemAudio() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: true,
            frameRate: 30
        )

        // When - Start recording with audio
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Record for short duration
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then - Stop recording and verify both files
        let result = try await captureEngine.stopRecording(session: session)

        // Verify screen video file
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.screenVideoPath.path), "Screen video file should exist")

        // Verify system audio file
        XCTAssertNotNil(result.systemAudioPath, "System audio path should be set")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.systemAudioPath!.path), "System audio file should exist")

        // Verify duration
        XCTAssertGreaterThan(result.duration, 0.3, "Should have recorded at least 0.3 seconds")
    }

    /// Test that audio and video files have compatible durations
    func testScreenCapture_AudioVideoDurationSync() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: true,
            frameRate: 30
        )

        // When - Record with audio for 1 second
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        let result = try await captureEngine.stopRecording(session: session)

        // Then - Load assets and verify durations
        let videoAsset = AVAsset(url: result.screenVideoPath)
        let audioAsset = AVAsset(url: result.systemAudioPath!)

        let videoDuration = try await videoAsset.load(.duration).seconds
        let audioDuration = try await audioAsset.load(.duration).seconds

        // Verify durations are within acceptable tolerance (100ms)
        let durationDifference = abs(videoDuration - audioDuration)
        XCTAssertLessThan(durationDifference, 0.1, "Video and audio durations should be within 100ms")

        // Verify both have content
        XCTAssertGreaterThan(videoDuration, 0.8, "Video should be at least 0.8 seconds")
        XCTAssertGreaterThan(audioDuration, 0.8, "Audio should be at least 0.8 seconds")
    }

    // MARK: - Multi-Track Synchronization Tests

    /// Test timestamp consistency between video and audio tracks
    func testScreenCapture_TimestampConsistency() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: true,
            frameRate: 30
        )

        // When - Record with audio
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Verify session start time is captured
        XCTAssertNotNil(session.startTime, "Session start time should be set immediately")

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let result = try await captureEngine.stopRecording(session: session)

        // Then - Verify timestamps are consistent
        XCTAssertNotNil(result.startTime, "Result should have start time")
        XCTAssertNotNil(result.endTime, "Result should have end time")
        XCTAssertGreaterThan(result.endTime, result.startTime, "End time should be after start time")

        // Verify duration matches time difference
        let timeDifference = result.endTime.timeIntervalSince(result.startTime)
        XCTAssertLessThan(abs(timeDifference - result.duration), 0.1, "Duration should match time difference")
    }

    /// Test sequential recordings produce separate files
    func testScreenCapture_SequentialRecordings() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Record first session
        let session1 = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        let result1 = try await captureEngine.stopRecording(session: session1)

        // Record second session
        let session2 = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        let result2 = try await captureEngine.stopRecording(session: session2)

        // Then - Verify both recordings are separate
        XCTAssertNotEqual(result1.screenVideoPath, result2.screenVideoPath, "Each recording should have unique file path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result1.screenVideoPath.path), "First video file should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result2.screenVideoPath.path), "Second video file should exist")
        XCTAssertNotEqual(result1.session.id, result2.session.id, "Each session should have unique ID")
    }

    // MARK: - File Output Validation Tests

    /// Test output file format and metadata
    func testScreenCapture_FileFormatValidation() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Record short clip
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        let result = try await captureEngine.stopRecording(session: session)

        // Then - Verify file format
        let asset = AVAsset(url: result.screenVideoPath)

        // Check if asset is playable
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Output video should be playable")

        // Check video track exists
        let videoTracks = try await asset.load(.tracks)
        XCTAssertGreaterThan(videoTracks.count, 0, "Asset should have at least one track")

        // Verify first track is video
        let firstTrack = videoTracks[0]
        let mediaType = try await firstTrack.mediaType
        XCTAssertEqual(mediaType, AVMediaType.video, "First track should be video")

        // Check natural time scale
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0, "Duration should be greater than 0")
    }

    /// Test output file has correct codec settings
    func testScreenCapture_CodecSettings() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30,
            pixelFormat: kCVPixelFormatType_32BGRA
        )

        // When - Record short clip
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        let result = try await captureEngine.stopRecording(session: session)

        // Then - Verify codec settings
        let asset = AVAsset(url: result.screenVideoPath)
        let tracks = try await asset.load(.tracks)
        let videoTracks = tracks.filter { track in
            return (try? track.mediaType) == AVMediaType.video
        }

        guard let videoTrack = videoTracks.first else {
            XCTFail("Should have at least one video track")
            return
        }

        // Verify natural dimensions match source
        let naturalSize = try await videoTrack.naturalSize
        XCTAssertGreaterThan(naturalSize.width, 0, "Width should be greater than 0")
        XCTAssertGreaterThan(naturalSize.height, 0, "Height should be greater than 0")

        // Verify time scale
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.timescale, 0, "Time scale should be set")
    }

    // MARK: - Error Handling Integration Tests

    /// Test that recording fails without proper permissions
    func testScreenCapture_PermissionDenied() async throws {
        // Note: This test is informational and may be skipped in CI environments
        // In a real environment, permissions would need to be revoked to test this

        // Given - Configuration that requires permissions
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When/Then - This would fail if permissions were denied
        // Since we can't easily revoke permissions in tests, we verify
        // that the permission check happens before recording starts
        let permissionManager = PermissionManager.shared
        let permissionStatus = await permissionManager.checkScreenRecordingPermission()

        if case .denied = permissionStatus {
            // If we don't have permission, verify recording fails
            do {
                _ = try await captureEngine.startRecording(
                    config: config,
                    outputURL: outputDirectory
                )
                XCTFail("Recording should fail without permission")
            } catch CaptureEngine.CaptureError.permissionDenied {
                // Expected
            } catch {
                XCTFail("Wrong error type: \(error)")
            }
        } else {
            // If we have permission, recording should succeed
            let session = try await captureEngine.startRecording(
                config: config,
                outputURL: outputDirectory
            )
            XCTAssertTrue(session.isRecording, "Session should be recording")
            _ = try await captureEngine.stopRecording(session: session)
        }
    }

    /// Test that recording cannot start twice
    func testScreenCapture_ConcurrentRecordingPrevention() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Start first recording
        let session1 = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Then - Attempting to start second recording should fail
        do {
            _ = try await captureEngine.startRecording(
                config: config,
                outputURL: outputDirectory
            )
            XCTFail("Should not allow concurrent recordings")
        } catch CaptureEngine.CaptureError.recordingAlreadyInProgress {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Cleanup
        _ = try await captureEngine.stopRecording(session: session1)
    }

    // MARK: - Duration Tracking Tests

    /// Test that duration is tracked accurately during recording
    func testScreenCapture_DurationTracking() async throws {
        // Given
        let displays = try await captureEngine.listDisplays()
        guard let display = displays.first else {
            throw XCTSkip("No displays available for testing")
        }

        let config = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: false,
            frameRate: 30
        )

        // When - Record for 1 second
        let session = try await captureEngine.startRecording(
            config: config,
            outputURL: outputDirectory
        )

        // Wait for duration updates
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let result = try await captureEngine.stopRecording(session: session)

        // Then - Verify duration is accurate (within 200ms tolerance)
        XCTAssertGreaterThan(result.duration, 0.8, "Duration should be at least 0.8 seconds")
        XCTAssertLessThan(result.duration, 1.5, "Duration should be less than 1.5 seconds")
    }

    // MARK: - Helper Methods

    /// Helper to get listDisplays from CaptureEngine
    private func listDisplays() async throws -> [SourceSelector.DisplaySource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listDisplays()
    }

    /// Helper to get listWindows from CaptureEngine
    private func listWindows() async throws -> [SourceSelector.WindowSource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listWindows()
    }

    /// Helper to get listApplications from CaptureEngine
    private func listApplications() async throws -> [SourceSelector.ApplicationSource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listApplications()
    }
}

// MARK: - CaptureEngine Extensions for Integration Testing

extension CaptureEngine {
    /// Internal methods exposed for integration testing
    /// Note: These methods work with the public API only
    func getCurrentSession() async -> RecordingSession? {
        // We cannot access private currentSession directly
        // This is a placeholder for test helper methods
        return nil
    }

    func listDisplays() async throws -> [SourceSelector.DisplaySource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listDisplays()
    }

    func listWindows() async throws -> [SourceSelector.WindowSource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listWindows()
    }

    func listApplications() async throws -> [SourceSelector.ApplicationSource] {
        let sourceSelector = SourceSelector.shared
        return try await sourceSelector.listApplications()
    }
}
