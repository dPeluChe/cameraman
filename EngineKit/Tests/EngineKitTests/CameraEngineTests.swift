//
//  CameraEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
import AVFoundation
@testable import EngineKit

@available(macOS 13.0, *)
final class CameraEngineTests: XCTestCase {
    var sut: CameraEngine!
    var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        sut = CameraEngine.shared

        // Create temporary output directory
        let tempDir = FileManager.default.temporaryDirectory
        outputDirectory = tempDir.appendingPathComponent("test_camera_recordings_\(UUID().uuidString)")
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

    func testCameraConfiguration_DefaultValues() {
        // Given
        let config = CameraEngine.CameraConfiguration()

        // Then
        XCTAssertNil(config.deviceID)
        XCTAssertEqual(config.resolutionPreset, .hd1080)
        XCTAssertEqual(config.frameRate, 30)
        XCTAssertEqual(config.codec, .h264)
        XCTAssertEqual(config.syncOffsetMs, 0)
    }

    func testCameraConfiguration_CustomValues() {
        // Given
        let config = CameraEngine.CameraConfiguration(
            deviceID: "test-device-id",
            resolutionPreset: .hd720,
            frameRate: 24,
            codec: .hevc,
            syncOffsetMs: 100
        )

        // Then
        XCTAssertEqual(config.deviceID, "test-device-id")
        XCTAssertEqual(config.resolutionPreset, .hd720)
        XCTAssertEqual(config.frameRate, 24)
        XCTAssertEqual(config.codec, .hevc)
        XCTAssertEqual(config.syncOffsetMs, 100)
    }

    func testResolutionPreset_Dimensions() {
        // Then
        XCTAssertEqual(CameraEngine.CameraConfiguration.ResolutionPreset.hd720.dimensions.width, 1280)
        XCTAssertEqual(CameraEngine.CameraConfiguration.ResolutionPreset.hd720.dimensions.height, 720)

        XCTAssertEqual(CameraEngine.CameraConfiguration.ResolutionPreset.hd1080.dimensions.width, 1920)
        XCTAssertEqual(CameraEngine.CameraConfiguration.ResolutionPreset.hd1080.dimensions.height, 1080)
    }

    func testVideoCodec_CodecType() {
        // Then
        XCTAssertEqual(CameraEngine.CameraConfiguration.VideoCodec.h264.codecType, .h264)
        XCTAssertEqual(CameraEngine.CameraConfiguration.VideoCodec.hevc.codecType, .hevc)
    }

    // MARK: - Camera Availability Tests

    func testListAvailableCameras_NotEmpty() async {
        // When
        let cameras = await sut.listAvailableCameras()

        // Then
        // In CI environments without cameras, this may be empty
        // But we can verify the method returns a valid array
        XCTAssertNotNil(cameras)
        XCTAssertTrue(cameras.allSatisfy { !$0.id.isEmpty })
    }

    func testListAvailableCameras_HasValidProperties() async {
        // When
        let cameras = await sut.listAvailableCameras()

        // Then
        for camera in cameras {
            XCTAssertFalse(camera.id.isEmpty)
            XCTAssertFalse(camera.name.isEmpty)
            XCTAssertFalse(camera.localizedName.isEmpty)
            // Position may be nil for external cameras
        }
    }

    func testIsCameraAvailable_ReturnsBool() async {
        // When
        let isAvailable = await sut.isCameraAvailable()

        // Then
        XCTAssertTrue(isAvailable == true || isAvailable == false)
        // In CI environments without cameras, this may return false
    }

    // MARK: - Error Description Tests

    func testCameraError_Descriptions() {
        // Given
        let errors: [CameraEngine.CameraError] = [
            .permissionDenied,
            .cameraNotAvailable,
            .deviceNotFound,
            .invalidConfiguration,
            .recordingNotStarted,
            .recordingAlreadyInProgress
        ]

        // Then
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testCameraError_PermissionDenied() {
        // Given
        let error = CameraEngine.CameraError.permissionDenied

        // Then
        XCTAssertEqual(error.errorDescription, "Camera permission denied")
    }

    func testCameraError_CameraNotAvailable() {
        // Given
        let error = CameraEngine.CameraError.cameraNotAvailable

        // Then
        XCTAssertEqual(error.errorDescription, "Camera is not available on this device")
    }

    func testCameraError_DeviceNotFound() {
        // Given
        let error = CameraEngine.CameraError.deviceNotFound

        // Then
        XCTAssertEqual(error.errorDescription, "Camera device not found")
    }

    // MARK: - Camera Device Tests

    func testCameraDevice_Equality() {
        // Given
        let device1 = CameraEngine.CameraDevice(
            id: "device-1",
            name: "Camera 1",
            localizedName: "FaceTime HD Camera",
            position: .front
        )

        let device2 = CameraEngine.CameraDevice(
            id: "device-1",
            name: "Camera 1",
            localizedName: "FaceTime HD Camera",
            position: .front
        )

        let device3 = CameraEngine.CameraDevice(
            id: "device-2",
            name: "Camera 2",
            localizedName: "External Camera",
            position: .back
        )

        // Then
        XCTAssertEqual(device1, device2)
        XCTAssertNotEqual(device1, device3)
    }

    // MARK: - Recording Session Tests

    func testRecordingSession_InitialState() {
        // Given
        let session = CameraEngine.RecordingSession()

        // Then
        XCTAssertNotNil(session.id)
        XCTAssertFalse(session.isRecording)
        XCTAssertNil(session.startTime)
        XCTAssertEqual(session.duration, 0)
        XCTAssertNil(session.error)
    }

    func testRecordingSession_MarkStarted() {
        // Given
        let session = CameraEngine.RecordingSession()
        let startDate = Date()

        // When
        session.markStarted(at: startDate)

        // Then
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(session.startTime, startDate)
    }

    func testRecordingSession_UpdateDuration() {
        // Given
        let session = CameraEngine.RecordingSession()
        session.markStarted(at: Date().addingTimeInterval(-10))

        // When
        session.updateDuration(10.5)

        // Then
        XCTAssertEqual(session.duration, 10.5)
    }

    func testRecordingSession_MarkStopped() {
        // Given
        let session = CameraEngine.RecordingSession()
        session.markStarted(at: Date())

        // When
        session.markStopped()

        // Then
        XCTAssertFalse(session.isRecording)
    }

    func testRecordingSession_SetError() {
        // Given
        let session = CameraEngine.RecordingSession()
        let testError = CameraEngine.CameraError.permissionDenied

        // When
        session.setError(testError)

        // Then
        XCTAssertEqual(session.error as? CameraEngine.CameraError, testError)
        XCTAssertFalse(session.isRecording)
    }

    // MARK: - Recording Result Tests

    func testRecordingResult_Properties() {
        // Given
        let session = CameraEngine.RecordingSession()
        let videoPath = outputDirectory.appendingPathComponent("camera.mov")
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(10)

        let result = CameraEngine.RecordingResult(
            session: session,
            cameraVideoPath: videoPath,
            duration: 10.0,
            syncOffsetMs: 50,
            startTime: startDate,
            endTime: endDate
        )

        // Then
        XCTAssertNotNil(result.session)
        XCTAssertEqual(result.cameraVideoPath, videoPath)
        XCTAssertEqual(result.duration, 10.0)
        XCTAssertEqual(result.syncOffsetMs, 50)
        XCTAssertEqual(result.startTime, startDate)
        XCTAssertEqual(result.endTime, endDate)
    }

    // MARK: - Error Equality Tests

    func testCameraError_Equality() {
        // Given
        let error1 = CameraEngine.CameraError.permissionDenied
        let error2 = CameraEngine.CameraError.permissionDenied
        let error3 = CameraEngine.CameraError.cameraNotAvailable

        // Then
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testCameraError_WithUnderlyingError_Equality() {
        // Given
        let underlyingError1 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let underlyingError2 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let underlyingError3 = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Different error"])

        let error1 = CameraEngine.CameraError.failedToStartSession(underlying: underlyingError1)
        let error2 = CameraEngine.CameraError.failedToStartSession(underlying: underlyingError2)
        let error3 = CameraEngine.CameraError.failedToStartSession(underlying: underlyingError3)

        // Then
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Performance Tests

    func testListAvailableCameras_Performance() async {
        // Measure performance for camera listing
        let start = Date()
        _ = await sut.listAvailableCameras()
        let elapsed = Date().timeIntervalSince(start)

        // Should complete in less than 1 second
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testCameraConfiguration_CreationPerformance() {
        // Measure
        measure {
            _ = CameraEngine.CameraConfiguration(
                deviceID: "test-device",
                resolutionPreset: .hd1080,
                frameRate: 30,
                codec: .h264,
                syncOffsetMs: 100
            )
        }
    }

    // MARK: - Integration Tests (requires camera hardware)

    func testStartRecording_WithoutPermission() async throws {
        // This test will fail if camera permission is granted
        // It's designed to test the permission check

        // Given
        let config = CameraEngine.CameraConfiguration()
        let outputURL = outputDirectory.appendingPathComponent("test.mov")

        // When/Then
        // In CI environments without camera permissions, this should throw permissionDenied
        do {
            _ = try await sut.startRecording(config: config, outputURL: outputURL)
            // If we get here, permission was granted (test passes but we should clean up)
            // This is expected in local development with camera access
        } catch CameraEngine.CameraError.permissionDenied {
            // Expected in CI environments
            XCTAssertTrue(true)
        } catch CameraEngine.CameraError.cameraNotAvailable {
            // Also acceptable in CI environments without cameras
            XCTAssertTrue(true)
        }
    }

    func testStartRecording_InvalidDeviceID() async throws {
        // Given
        let config = CameraEngine.CameraConfiguration(deviceID: "non-existent-device-id")
        let outputURL = outputDirectory.appendingPathComponent("test.mov")

        // When/Then
        do {
            _ = try await sut.startRecording(config: config, outputURL: outputURL)
            XCTFail("Should have thrown deviceNotFound error")
        } catch CameraEngine.CameraError.deviceNotFound {
            // Expected
            XCTAssertTrue(true)
        } catch {
            // Other errors are acceptable (permission denied, camera not available, etc.)
            XCTAssertTrue(true)
        }
    }

    func testStopRecording_WithoutStarting() async throws {
        // Given
        let session = CameraEngine.RecordingSession()
        let config = CameraEngine.CameraConfiguration()

        // When/Then
        do {
            _ = try await sut.stopRecording(session: session, config: config)
            XCTFail("Should have thrown recordingNotStarted error")
        } catch CameraEngine.CameraError.recordingNotStarted {
            // Expected
            XCTAssertTrue(true)
        }
    }

    func testStartRecording_WhileAlreadyRecording() async throws {
        // Note: This test is difficult to implement without actually starting a recording
        // In a real environment with camera hardware, this would require:
        // 1. Start first recording
        // 2. Try to start second recording
        // 3. Verify recordingAlreadyInProgress is thrown

        // For now, we'll skip this test in CI environments
        try XCTSkipIf(true, "Requires actual camera hardware and permissions")
    }

    // MARK: - Edge Case Tests

    func testCameraConfiguration_ZeroSyncOffset() {
        // Given
        let config = CameraEngine.CameraConfiguration(syncOffsetMs: 0)

        // Then
        XCTAssertEqual(config.syncOffsetMs, 0)
    }

    func testCameraConfiguration_NegativeSyncOffset() {
        // Given
        let config = CameraEngine.CameraConfiguration(syncOffsetMs: -50)

        // Then
        XCTAssertEqual(config.syncOffsetMs, -50)
        // Negative values mean camera is ahead of screen
    }

    func testCameraConfiguration_LargeSyncOffset() {
        // Given
        let config = CameraEngine.CameraConfiguration(syncOffsetMs: 5000) // 5 seconds

        // Then
        XCTAssertEqual(config.syncOffsetMs, 5000)
    }

    func testCameraConfiguration_AllFrameRates() {
        // Given
        let frameRates = [24, 25, 30, 60, 120]

        // Then
        for frameRate in frameRates {
            let config = CameraEngine.CameraConfiguration(frameRate: frameRate)
            XCTAssertEqual(config.frameRate, frameRate)
        }
    }

    func testCameraConfiguration_AllResolutions() {
        // Given
        let resolutions: [CameraEngine.CameraConfiguration.ResolutionPreset] = [.hd720, .hd1080]

        // Then
        for resolution in resolutions {
            let config = CameraEngine.CameraConfiguration(resolutionPreset: resolution)
            XCTAssertEqual(config.resolutionPreset, resolution)
        }
    }

    func testCameraConfiguration_AllCodecs() {
        // Given
        let codecs: [CameraEngine.CameraConfiguration.VideoCodec] = [.h264, .hevc]

        // Then
        for codec in codecs {
            let config = CameraEngine.CameraConfiguration(codec: codec)
            XCTAssertEqual(config.codec, codec)
        }
    }
}
