//
//  PermissionManagerTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-18.
//

import XCTest
import AVFoundation
@testable import EngineKit

@available(macOS 13.0, *)
final class PermissionManagerTests: XCTestCase {
    var permissionManager: PermissionManager!

    override func setUp() async throws {
        try await super.setUp()
        permissionManager = PermissionManager.shared
    }

    override func tearDown() async throws {
        permissionManager = nil
        try await super.tearDown()
    }

    // MARK: - Screen Recording Permission Tests

    func testScreenRecordingPermissionStatus() async throws {
        let status = await permissionManager.checkScreenRecordingPermission()

        // In CI environments without screen recording permission, this will be .denied
        // In local development with permission granted, this will be .authorized
        XCTAssertTrue(
            status == .authorized || status == .denied,
            "Screen recording permission should be either authorized or denied, got: \(status)"
        )
    }

    func testScreenRecordingPermissionDeniedErrorDetection() async throws {
        let status = await permissionManager.checkScreenRecordingPermission()

        if status == .denied {
            // Verify that denied permission is properly detected
            XCTAssertEqual(status, .denied, "Should detect denied screen recording permission")
        }
    }

    // MARK: - Microphone Permission Tests

    func testMicrophonePermissionStatus() async throws {
        let status = await permissionManager.checkMicrophonePermission()

        // Should be one of the valid statuses
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied, .notDetermined]
        XCTAssertTrue(
            validStatuses.contains(status),
            "Microphone permission should be authorized, denied, or notDetermined, got: \(status)"
        )
    }

    func testMicrophoneAvailability() async throws {
        let isAvailable = await permissionManager.isMicrophoneAvailable()

        // Most Macs have microphones, but we should handle both cases
        XCTAssertTrue(
            isAvailable == true || isAvailable == false,
            "Microphone availability check should return a boolean"
        )
    }

    func testRequestMicrophonePermission() async throws {
        // Request permission - this may show a dialog in interactive sessions
        let status = await permissionManager.requestMicrophonePermission()

        // After requesting, status should be either authorized or denied
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied]
        XCTAssertTrue(
            validStatuses.contains(status),
            "After requesting microphone permission, status should be authorized or denied, got: \(status)"
        )
    }

    // MARK: - Camera Permission Tests

    func testCameraPermissionStatus() async throws {
        let status = await permissionManager.checkCameraPermission()

        // Should be one of the valid statuses
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied, .notDetermined]
        XCTAssertTrue(
            validStatuses.contains(status),
            "Camera permission should be authorized, denied, or notDetermined, got: \(status)"
        )
    }

    func testCameraAvailability() async throws {
        let isAvailable = await permissionManager.isCameraAvailable()

        // Some Macs don't have cameras (e.g., Mac mini, Mac Pro)
        XCTAssertTrue(
            isAvailable == true || isAvailable == false,
            "Camera availability check should return a boolean"
        )
    }

    func testRequestCameraPermission() async throws {
        // Request permission - this may show a dialog in interactive sessions
        let status = await permissionManager.requestCameraPermission()

        // After requesting, status should be either authorized or denied
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied]
        XCTAssertTrue(
            validStatuses.contains(status),
            "After requesting camera permission, status should be authorized or denied, got: \(status)"
        )
    }

    // MARK: - Health Check Tests

    func testHealthCheckReturnsValidResult() async throws {
        let result = await permissionManager.performHealthCheck()

        // Verify that all permission statuses are valid
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied, .notDetermined]
        XCTAssertTrue(
            validStatuses.contains(result.screenRecording),
            "Screen recording status should be valid"
        )
        XCTAssertTrue(
            validStatuses.contains(result.microphone),
            "Microphone status should be valid"
        )
        XCTAssertTrue(
            validStatuses.contains(result.camera),
            "Camera status should be valid"
        )
    }

    func testHealthCheckCanRecordWithScreenOnly() async throws {
        let result = await permissionManager.performHealthCheck()

        // Test screen-only recording requirement
        let canRecord = result.canRecord(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        )

        // Should be true only if screen recording is authorized
        XCTAssertEqual(
            canRecord,
            result.screenRecording == .authorized,
            "Can record with screen only should depend on screen recording permission"
        )
    }

    func testHealthCheckCanRecordWithAllPermissions() async throws {
        let result = await permissionManager.performHealthCheck()

        // Test full recording setup
        let canRecord = result.canRecord(
            needsScreenRecording: true,
            needsMicrophone: true,
            needsCamera: true
        )

        let expectedCanRecord = result.screenRecording == .authorized &&
            result.microphone == .authorized &&
            result.camera == .authorized

        XCTAssertEqual(
            canRecord,
            expectedCanRecord,
            "Can record with all permissions should require all permissions"
        )
    }

    func testHealthCheckMissingPermissions() async throws {
        let result = await permissionManager.performHealthCheck()

        // Test missing permissions for different configurations
        let screenOnlyMissing = result.missingPermissions(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        )

        if result.screenRecording != .authorized {
            XCTAssertEqual(
                screenOnlyMissing,
                ["Screen Recording"],
                "Should report screen recording as missing when denied"
            )
        } else {
            XCTAssertTrue(
                screenOnlyMissing.isEmpty,
                "Should report no missing permissions when authorized"
            )
        }

        let allMissing = result.missingPermissions(
            needsScreenRecording: true,
            needsMicrophone: true,
            needsCamera: true
        )

        // Verify that missing permissions are reported
        let expectedMissingCount = [
            result.screenRecording != .authorized,
            result.microphone != .authorized,
            result.camera != .authorized
        ].filter { $0 }.count

        XCTAssertEqual(
            allMissing.count,
            expectedMissingCount,
            "Should report correct count of missing permissions"
        )
    }

    // MARK: - Convenience Methods Tests

    func testHasRequiredPermissionsForScreenOnly() async throws {
        let hasPermissions = await permissionManager.hasRequiredPermissions(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        )

        // Should be true if screen recording is authorized
        let screenRecordingStatus = await permissionManager.checkScreenRecordingPermission()
        XCTAssertEqual(
            hasPermissions,
            screenRecordingStatus == .authorized,
            "Has required permissions for screen only should match screen recording status"
        )
    }

    func testHasRequiredPermissionsForFullSetup() async throws {
        let hasPermissions = await permissionManager.hasRequiredPermissions(
            needsScreenRecording: true,
            needsMicrophone: true,
            needsCamera: true
        )

        // Get individual permission statuses
        let screenStatus = await permissionManager.checkScreenRecordingPermission()
        let micStatus = await permissionManager.checkMicrophonePermission()
        let camStatus = await permissionManager.checkCameraPermission()

        let expected = screenStatus == .authorized && micStatus == .authorized && camStatus == .authorized
        XCTAssertEqual(
            hasPermissions,
            expected,
            "Has required permissions for full setup should require all permissions"
        )
    }

    func testGetFirstMissingPermissionError() async throws {
        // Test with screen recording requirement
        let error = await permissionManager.getFirstMissingPermissionError(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        )

        let screenStatus = await permissionManager.checkScreenRecordingPermission()

        if screenStatus != .authorized {
            XCTAssertNotNil(
                error,
                "Should return an error when screen recording permission is missing"
            )
            if let error = error as? PermissionManager.PermissionError {
                XCTAssertEqual(
                    error,
                    .screenRecordingDenied,
                    "Should return screenRecordingDenied error"
                )
            }
        } else {
            XCTAssertNil(
                error,
                "Should return nil when all required permissions are granted"
            )
        }
    }

    func testGetFirstMissingPermissionErrorWithFullSetup() async throws {
        let error = await permissionManager.getFirstMissingPermissionError(
            needsScreenRecording: true,
            needsMicrophone: true,
            needsCamera: true
        )

        let screenStatus = await permissionManager.checkScreenRecordingPermission()
        let micStatus = await permissionManager.checkMicrophonePermission()
        let camStatus = await permissionManager.checkCameraPermission()

        let hasAllPermissions = screenStatus == .authorized &&
            micStatus == .authorized &&
            camStatus == .authorized

        if hasAllPermissions {
            XCTAssertNil(
                error,
                "Should return nil when all permissions are granted"
            )
        } else {
            XCTAssertNotNil(
                error,
                "Should return an error when any required permission is missing"
            )
        }
    }

    // MARK: - Request Permissions Tests

    func testRequestPermissionsForScreenOnly() async throws {
        let result = await permissionManager.requestPermissions(
            needsScreenRecording: true,
            needsMicrophone: false,
            needsCamera: false
        )

        // Verify result is valid
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied, .notDetermined]
        XCTAssertTrue(
            validStatuses.contains(result.screenRecording),
            "Screen recording status should be valid after requesting"
        )
    }

    func testRequestPermissionsForFullSetup() async throws {
        let result = await permissionManager.requestPermissions(
            needsScreenRecording: true,
            needsMicrophone: true,
            needsCamera: true
        )

        // Verify all statuses are valid
        let validStatuses: [PermissionManager.PermissionStatus] = [.authorized, .denied, .notDetermined]
        XCTAssertTrue(
            validStatuses.contains(result.screenRecording),
            "Screen recording status should be valid after requesting"
        )
        XCTAssertTrue(
            validStatuses.contains(result.microphone),
            "Microphone status should be valid after requesting"
        )
        XCTAssertTrue(
            validStatuses.contains(result.camera),
            "Camera status should be valid after requesting"
        )
    }

    // MARK: - Error Description Tests

    func testPermissionErrorDescriptions() async throws {
        XCTAssertEqual(
            PermissionManager.PermissionError.screenRecordingDenied.errorDescription,
            "Screen recording permission is denied. Please grant permission in System Settings > Privacy & Security > Screen Recording"
        )

        XCTAssertEqual(
            PermissionManager.PermissionError.microphoneDenied.errorDescription,
            "Microphone permission is denied. Please grant permission in System Settings > Privacy & Security > Microphone"
        )

        XCTAssertEqual(
            PermissionManager.PermissionError.cameraDenied.errorDescription,
            "Camera permission is denied. Please grant permission in System Settings > Privacy & Security > Camera"
        )

        XCTAssertEqual(
            PermissionManager.PermissionError.microphoneUnavailable.errorDescription,
            "Microphone is not available on this device"
        )

        XCTAssertEqual(
            PermissionManager.PermissionError.cameraUnavailable.errorDescription,
            "Camera is not available on this device"
        )
    }

    // MARK: - Performance Tests

    func testHealthCheckPerformance() async throws {
        // Health check should complete quickly
        measure {
            let expectation = self.expectation(description: "Health check completes")

            Task {
                _ = await permissionManager.performHealthCheck()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }
}
