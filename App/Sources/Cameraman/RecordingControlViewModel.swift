//
//  RecordingControlViewModel.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import Combine
import AppKit
import CoreVideo
import EngineKit

/// View model for recording controls
@MainActor
class RecordingControlViewModel: ObservableObject {
    // Set to true to enable verbose recording logs
    private let debugLoggingEnabled = false

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime = "00:00"
    @Published var statusText = "Ready to record"
    @Published var includeCamera = true
    @Published var includeMicrophone = true
    @Published var includeSystemAudio = true
    @Published var lastRecordingURL: URL?
    @Published var recordingQuality: RecordingQuality = .native
    /// Selected capture area in display points (top-left origin). nil = full display.
    @Published var selectedArea: CGRect?

    // If set, the new recording will be added as a take to this project instead of creating a new one
    @Published var targetProjectId: ProjectId?

    private var selectedConfig: CaptureEngine.CaptureConfiguration?
    /// The currently selected display source (derived from selectedConfig).
    var selectedDisplaySource: SourceSelector.DisplaySource? { selectedConfig?.display }

    private var timer: Timer?
    private var recordingSession: Recorder.RecordingSession?
    private var recordingIndicator: RecordingIndicatorWindow?

    private func log(_ message: String) {
        if debugLoggingEnabled {
            print("[DEBUG-REC] \(message)")
        }
    }

    func configureSource(_ source: RecordingSourceSelectorView.CaptureSource) async {
        // Reset area selection when source changes
        selectedArea = nil

        // Convert UI selection to CaptureConfiguration
        switch source {
        case .display(let displaySource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: displaySource,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
            statusText = "Selected: \(displaySource.name)"

        case .window(let windowSource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .window,
                window: windowSource,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
            statusText = "Selected: \(windowSource.title)"

        case .application(let appSource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .application,
                application: appSource,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
            statusText = "Selected: \(appSource.name)"
        }
    }

    func startRecording() async {
        log("startRecording() called")
        guard !isRecording else {
            log("Already recording, ignoring start request")
            return
        }

        guard let config = selectedConfig else {
            log("No configuration selected")
            statusText = "Please select a source first"
            return
        }

        log("Configuration selected: \(config)")
        statusText = "Requesting permissions..."
        do {
            var includeCameraForSession = includeCamera
            var includeMicrophoneForSession = includeMicrophone

            // Check permissions first
            log("Requesting screen permission...")
            let permissionManager = PermissionManager.shared
            let screenPermission = await permissionManager.requestScreenRecordingPermission()
            log("Screen permission result: \(screenPermission)")
            guard screenPermission == .authorized else {
                log("Screen permission denied")
                statusText = "Screen recording permission denied"
                return
            }

            if includeCameraForSession {
                log("Requesting camera permission...")
                let cameraPermission = await permissionManager.requestCameraPermission()
                log("Camera permission result: \(cameraPermission)")

                if cameraPermission != .authorized {
                    log("Camera permission denied. Disabling camera but continuing recording.")
                    // Don't abort, just disable camera for this session
                    includeCameraForSession = false
                    // Update status to warn user
                    statusText = "Camera denied - Recording Screen Only"
                    // Continue...
                }
            }

            if includeMicrophoneForSession {
                log("Requesting microphone permission...")
                let micPermission = await permissionManager.requestMicrophonePermission()
                log("Microphone permission result: \(micPermission)")

                if micPermission != .authorized {
                    log("Microphone permission denied. Disabling mic but continuing recording.")
                    includeMicrophoneForSession = false
                    statusText = "Mic denied - Recording Screen Only"
                }
            }

            statusText = "Starting recording..."
            log("Permissions OK. Preparing output URL...")

            // Create output URL (directory for all recording files)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings")
            try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            // NOTE: outputURL is a DIRECTORY, not a file. Recorder will create screen.mov, camera.mov, etc. inside it
            let outputURL = recordingsPath.appendingPathComponent("recording_\(timestamp)")
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            log("Output directory: \(outputURL.path)")

            // Recreate config with current system audio + quality + area settings
            let screenConfig = CaptureEngine.CaptureConfiguration(
                sourceType: config.sourceType,
                display: config.display,
                window: config.window,
                application: config.application,
                captureSystemAudio: includeSystemAudio,
                frameRate: config.frameRate,
                pixelFormat: config.pixelFormat,
                quality: recordingQuality,
                captureRect: selectedArea
            )

            // Create camera configuration if needed
            var cameraConfig: CameraEngine.CameraConfiguration?
            if includeCameraForSession {
                cameraConfig = CameraEngine.CameraConfiguration(
                    deviceID: nil, // Use default camera
                    resolutionPreset: .hd1080,
                    frameRate: 30,
                    codec: .h264,
                    syncOffsetMs: 0
                )
            }

            // Create recording configuration
            let config = Recorder.RecordingConfiguration(
                screenConfig: screenConfig,
                cameraConfig: cameraConfig,
                captureMicAudio: includeMicrophoneForSession
            )

            // Start recording
            log("Calling Recorder.shared.startRecording...")
            let recorder = Recorder.shared
            recordingSession = try await recorder.startRecording(
                config: config,
                outputURL: outputURL
            )
            log("Recorder started successfully. Session: \(String(describing: recordingSession))")

            // Start timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.updateElapsedTime()
                }
            }

            statusText = "Recording..."
            isRecording = true

            // Show recording indicator
            recordingIndicator = RecordingIndicatorWindow()
            recordingIndicator?.show()
            if debugLoggingEnabled { print("📹 Recording indicator shown") }

        } catch {
            statusText = "Error: \(error.localizedDescription)"
            log("Failed to start recording: \(error)")
            if debugLoggingEnabled { dump(error) }

            // Clean up state
            isRecording = false
            recordingSession = nil
            timer?.invalidate()
            timer = nil
        }
    }

    func stopRecording() async {
        guard isRecording, let session = recordingSession else { return }

        statusText = "Stopping recording..."

        // Stop timer
        timer?.invalidate()
        timer = nil

        do {
            let recorder = Recorder.shared
            let result = try await recorder.stopRecording(session: session)

            lastRecordingURL = result.screenVideoPath
            statusText = "Saved: \(result.screenVideoPath.lastPathComponent)"
            print("✅ Recording saved to: \(result.screenVideoPath)")
            print("   Duration: \(result.duration)s")

            let library = ProjectLibrary.shared
            
            if let targetId = targetProjectId {
                _ = try await library.addTake(projectId: targetId, recordingResult: result)
                statusText = "Take added to project"
                print("✅ Take added to project: \(targetId)")
                
                // Notify editor to refresh
                NotificationCenter.default.post(name: .projectUpdated, object: targetId)
                
                // Reset target after successful add
                targetProjectId = nil
            } else {
                let projectId = try await library.createProject(from: result)

                // Open the editor for the newly created project
                NotificationCenter.default.post(name: .openProject, object: projectId)
            }

            if let cameraPath = result.cameraVideoPath {
                print("   Camera: \(cameraPath.lastPathComponent)")
            }
            if let micPath = result.micAudioPath {
                print("   Mic audio: \(micPath.lastPathComponent)")
            }
        } catch {
            statusText = "Error: \(error.localizedDescription)"
            print("❌ Failed to stop recording: \(error)")
        }

        isRecording = false
        isPaused = false
        elapsedTime = "00:00"
        recordingSession = nil

        // Hide recording indicator
        recordingIndicator?.hide()
        recordingIndicator = nil
        print("📹 Recording indicator hidden")
    }

    func pauseResumeRecording() async {
        guard isRecording, recordingSession != nil else { return }

        if isPaused {
            statusText = "Resuming..."
            // TODO: Implement pause/resume in Recorder
            isPaused = false
            statusText = "Recording..."
        } else {
            statusText = "Pausing..."
            // TODO: Implement pause/resume in Recorder
            isPaused = true
            statusText = "Paused"
        }
    }

    private func updateElapsedTime() async {
        guard let session = recordingSession else { return }

        // Calculate elapsed time from session
        if let start = session.startTime {
            let elapsed = Date().timeIntervalSince(start)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            elapsedTime = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func showLastRecordingInFinder() {
        guard let url = lastRecordingURL else {
            print("No recording to show")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openRecordingsFolder() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings")
        NSWorkspace.shared.open(recordingsPath)
    }
}
