//
//  PermissionManager.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import os.log
import AppKit

/// PermissionManager handles checking and requesting permissions for screen recording, microphone, and camera access.
/// Provides health check functionality to verify all required permissions are granted.
public actor PermissionManager {
    /// Errors that can occur during permission checks
    public enum PermissionError: Error, LocalizedError {
        case screenRecordingDenied
        case microphoneDenied
        case cameraDenied
        case microphoneUnavailable
        case cameraUnavailable

        public var errorDescription: String? {
            switch self {
            case .screenRecordingDenied:
                return "Screen recording permission is denied. Please grant permission in System Settings > Privacy & Security > Screen Recording"
            case .microphoneDenied:
                return "Microphone permission is denied. Please grant permission in System Settings > Privacy & Security > Microphone"
            case .cameraDenied:
                return "Camera permission is denied. Please grant permission in System Settings > Privacy & Security > Camera"
            case .microphoneUnavailable:
                return "Microphone is not available on this device"
            case .cameraUnavailable:
                return "Camera is not available on this device"
            }
        }
    }

    /// Permission status for a specific permission type
    public enum PermissionStatus {
        case authorized
        case denied
        case notDetermined
    }

    /// Health check result containing permission statuses
    public struct HealthCheckResult {
        public let screenRecording: PermissionStatus
        public let microphone: PermissionStatus
        public let camera: PermissionStatus
        public let isHealthy: Bool

        /// Check if all required permissions for a specific recording configuration are granted
        /// - Parameters:
        ///   - needsScreenRecording: Whether screen recording permission is required
        ///   - needsMicrophone: Whether microphone permission is required
        ///   - needsCamera: Whether camera permission is required
        /// - Returns: true if all required permissions are granted
        public func canRecord(
            needsScreenRecording: Bool = true,
            needsMicrophone: Bool = false,
            needsCamera: Bool = false
        ) -> Bool {
            if needsScreenRecording && screenRecording != .authorized {
                return false
            }
            if needsMicrophone && microphone != .authorized {
                return false
            }
            if needsCamera && camera != .authorized {
                return false
            }
            return true
        }

        /// Get a description of any missing permissions
        /// - Parameters:
        ///   - needsScreenRecording: Whether screen recording permission is required
        ///   - needsMicrophone: Whether microphone permission is required
        ///   - needsCamera: Whether camera permission is required
        /// - Returns: Array of missing permission descriptions
        public func missingPermissions(
            needsScreenRecording: Bool = true,
            needsMicrophone: Bool = false,
            needsCamera: Bool = false
        ) -> [String] {
            var missing: [String] = []
            if needsScreenRecording && screenRecording != .authorized {
                missing.append("Screen Recording")
            }
            if needsMicrophone && microphone != .authorized {
                missing.append("Microphone")
            }
            if needsCamera && camera != .authorized {
                missing.append("Camera")
            }
            return missing
        }
    }

    /// Shared instance
    public static let shared = PermissionManager()

    private init() {}

    // MARK: - Screen Recording Permission

    /// Check screen recording permission status
    /// - Returns: Permission status for screen recording
    public func checkScreenRecordingPermission() async -> PermissionStatus {
        // Since CGPreflightScreenCaptureAccess and CGRequestScreenCaptureAccess are deprecated in macOS 15,
        // and SCShareableContent throws an error if permission is denied,
        // we'll rely on SCShareableContent.excludingDesktopWindows.
        
        do {
            // This call will fail if permission is denied
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return .authorized
        } catch {
            let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "PermissionManager")
            logger.warning("Permission check failed: \(error.localizedDescription)")
            return .denied
        }
    }

    /// Request screen recording permission
    /// Note: Screen recording permission must be granted manually in System Settings.
    /// This method will open the relevant system preference pane.
    /// - Returns: Permission status after attempting to request
    public func requestScreenRecordingPermission() async -> PermissionStatus {
        if await checkScreenRecordingPermission() == .authorized {
            return .authorized
        }

        // CGRequestScreenCaptureAccess shows the system prompt when undetermined AND
        // registers the app in System Settings > Screen Recording so it can be toggled
        // on later. SCShareableContent alone does not reliably add the app to that list.
        if CGRequestScreenCaptureAccess() {
            return .authorized
        }

        // Previously denied: macOS won't re-prompt, so guide the user to System Settings
        // (the app now appears there thanks to the request above).
        await openSystemSettings(for: .screenRecording)

        return await checkScreenRecordingPermission()
    }

    /// Privacy permissions that map to a System Settings pane.
    public enum Kind {
        case screenRecording, camera, microphone

        fileprivate var settingsAnchor: String {
            switch self {
            case .screenRecording: return "Privacy_ScreenCapture"
            case .camera: return "Privacy_Camera"
            case .microphone: return "Privacy_Microphone"
            }
        }
    }

    /// Open the System Settings > Privacy pane for a permission so the user can toggle it.
    public func openSystemSettings(for kind: Kind) async {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    // MARK: - Microphone Permission

    /// Check microphone permission status
    /// - Returns: Permission status for microphone
    public func checkMicrophonePermission() async -> PermissionStatus {
        await MainActor.run {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            switch status {
            case .authorized:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .denied
            @unknown default:
                return .denied
            }
        }
    }

    /// Request microphone permission
    /// - Returns: Permission status after requesting
    public func requestMicrophonePermission() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume()
            }
        }

        // Check status after request
        return await checkMicrophonePermission()
    }

    /// Check if microphone is available on this device
    /// - Returns: true if microphone is available
    public func isMicrophoneAvailable() async -> Bool {
        await MainActor.run {
            AVCaptureDevice.default(for: .audio) != nil
        }
    }

    // MARK: - Camera Permission

    /// Check camera permission status
    /// - Returns: Permission status for camera
    public func checkCameraPermission() async -> PermissionStatus {
        await MainActor.run {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .denied
            @unknown default:
                return .denied
            }
        }
    }

    /// Request camera permission
    /// - Returns: Permission status after requesting
    public func requestCameraPermission() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume()
            }
        }

        // Check status after request
        return await checkCameraPermission()
    }

    /// Check if camera is available on this device
    /// - Returns: true if camera is available
    public func isCameraAvailable() async -> Bool {
        await MainActor.run {
            AVCaptureDevice.default(for: .video) != nil
        }
    }

    // MARK: - Health Check

    /// Perform a comprehensive health check on all permissions
    /// - Returns: HealthCheckResult containing status of all permissions
    public func performHealthCheck() async -> HealthCheckResult {
        async let screenRecordingStatus = checkScreenRecordingPermission()
        async let microphoneStatus = checkMicrophonePermission()
        async let cameraStatus = checkCameraPermission()

        let (screenRecording, microphone, camera) = await (screenRecordingStatus, microphoneStatus, cameraStatus)

        let isHealthy = screenRecording == .authorized

        return HealthCheckResult(
            screenRecording: screenRecording,
            microphone: microphone,
            camera: camera,
            isHealthy: isHealthy
        )
    }

    /// Request all required permissions for a basic recording setup
    /// - Parameters:
        ///   - needsScreenRecording: Whether to request screen recording permission
        ///   - needsMicrophone: Whether to request microphone permission
        ///   - needsCamera: Whether to request camera permission
    /// - Returns: HealthCheckResult after requesting permissions
    public func requestPermissions(
        needsScreenRecording: Bool = true,
        needsMicrophone: Bool = false,
        needsCamera: Bool = false
    ) async -> HealthCheckResult {
        if needsScreenRecording {
            _ = await requestScreenRecordingPermission()
        }

        if needsMicrophone {
            _ = await requestMicrophonePermission()
        }

        if needsCamera {
            _ = await requestCameraPermission()
        }

        return await performHealthCheck()
    }

    // MARK: - Convenience Methods

    /// Check if all required permissions are granted for a recording session
    /// - Parameters:
        ///   - needsScreenRecording: Whether screen recording is required
        ///   - needsMicrophone: Whether microphone is required
        ///   - needsCamera: Whether camera is required
    /// - Returns: true if all required permissions are granted
    public func hasRequiredPermissions(
        needsScreenRecording: Bool = true,
        needsMicrophone: Bool = false,
        needsCamera: Bool = false
    ) async -> Bool {
        let healthCheck = await performHealthCheck()
        return healthCheck.canRecord(
            needsScreenRecording: needsScreenRecording,
            needsMicrophone: needsMicrophone,
            needsCamera: needsCamera
        )
    }

    /// Get error for first missing permission
    /// - Parameters:
        ///   - needsScreenRecording: Whether screen recording is required
        ///   - needsMicrophone: Whether microphone is required
        ///   - needsCamera: Whether camera is required
    /// - Returns: PermissionError if any required permission is missing, nil otherwise
    public func getFirstMissingPermissionError(
        needsScreenRecording: Bool = true,
        needsMicrophone: Bool = false,
        needsCamera: Bool = false
    ) async -> PermissionError? {
        let healthCheck = await performHealthCheck()

        if needsScreenRecording && healthCheck.screenRecording != .authorized {
            return .screenRecordingDenied
        }

        if needsMicrophone {
            if healthCheck.microphone != .authorized {
                return .microphoneDenied
            }
            let micAvailable = await isMicrophoneAvailable()
            if !micAvailable {
                return .microphoneUnavailable
            }
        }

        if needsCamera {
            if healthCheck.camera != .authorized {
                return .cameraDenied
            }
            let cameraAvailable = await isCameraAvailable()
            if !cameraAvailable {
                return .cameraUnavailable
            }
        }

        return nil
    }
}
