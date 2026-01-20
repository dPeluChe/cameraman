//
//  App.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI
import EngineKit

/// Main app entry point
@main
struct CameramanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window with recording controls
        WindowGroup {
            AppNavigation()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            // Add Preferences menu item
            CommandGroup(replacing: .appSettings) {
                Button {
                    // Open preferences window
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Text("Preferences...")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// App delegate for managing lifecycle and hotkeys
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarMenu: StatusBarMenu?
    var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup hotkeys
        setupHotkeys()

        // Create status bar menu
        statusBarMenu = StatusBarMenu()

        // Note: Floating panel removed - using WindowGroup instead
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate when last window closes (floating panel manages lifecycle)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        hotkeyManager?.unregisterAllHotkeys()
    }

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager.shared

        // Set up event handler for hotkey actions
        hotkeyManager?.setEventHandler { [weak self] action in
            self?.handleHotkeyAction(action)
        }

        // Register default hotkeys
        do {
            try hotkeyManager?.registerDefaultHotkeys()
            print("✅ Default hotkeys registered successfully")
        } catch {
            print("❌ Failed to register hotkeys: \(error.localizedDescription)")
        }
    }

    private func handleHotkeyAction(_ action: HotkeyManager.Action) {
        Task { @MainActor in
            guard let viewModel = RecordingStateManager.shared.viewModel else {
                print("⚠️ Recording view model not available")
                return
            }

            switch action {
            case .startRecording:
                if !viewModel.isRecording {
                    await viewModel.startRecording()
                    print("▶️ Started recording via hotkey")
                } else {
                    print("⚠️ Recording already in progress")
                }

            case .stopRecording:
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                    print("⏹️ Stopped recording via hotkey")
                } else {
                    print("⚠️ No recording in progress")
                }

            case .pauseResumeRecording:
                if viewModel.isRecording {
                    await viewModel.pauseResumeRecording()
                    print(viewModel.isPaused ? "⏸️ Paused recording via hotkey" : "▶️ Resumed recording via hotkey")
                } else {
                    print("⚠️ No recording in progress")
                }

            case .toggleCamera:
                viewModel.includeCamera.toggle()
                print("📷 Camera toggled: \(viewModel.includeCamera ? "enabled" : "disabled")")

            case .toggleMicrophone:
                viewModel.includeMicrophone.toggle()
                print("🎤 Microphone toggled: \(viewModel.includeMicrophone ? "enabled" : "disabled")")
            }
        }
    }
}

/// Recording control UI
struct RecordingControlView: View {
    @StateObject private var viewModel = RecordingControlViewModel()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Recording Controls")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)

            Divider()
                .background(Color.white.opacity(0.2))

            // Status
            HStack {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)

                Text(viewModel.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)

                Spacer()

                if viewModel.isRecording {
                    Text(viewModel.elapsedTime)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)

            // Controls
            HStack(spacing: 12) {
                // Record/Stop button
                Button(action: {
                    if viewModel.isRecording {
                        Task { await viewModel.stopRecording() }
                    } else {
                        Task { await viewModel.startRecording() }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.green)
                            .frame(width: 50, height: 50)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Pause/Resume button
                if viewModel.isRecording {
                    Button(action: {
                        Task { await viewModel.pauseResumeRecording() }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 40, height: 40)

                            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Options
            VStack(spacing: 8) {
                Toggle("Camera", isOn: $viewModel.includeCamera)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                    .font(.system(size: 12))

                Toggle("Microphone", isOn: $viewModel.includeMicrophone)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                    .font(.system(size: 12))

                Toggle("System Audio", isOn: $viewModel.includeSystemAudio)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                    .font(.system(size: 12))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(width: 280, height: 200)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            // Share view model with status bar menu
            RecordingStateManager.shared.viewModel = viewModel
        }
    }
}

/// View model for recording controls
@MainActor
class RecordingControlViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime = "00:00"
    @Published var statusText = "Ready to record"
    @Published var includeCamera = true
    @Published var includeMicrophone = false
    @Published var includeSystemAudio = true

    private var timer: Timer?
    private var recordingSession: Recorder.RecordingSession?

    func startRecording() async {
        guard !isRecording else { return }

        statusText = "Requesting permissions..."
        do {
            // Check permissions first
            let permissionManager = PermissionManager.shared
            let screenPermission = await permissionManager.requestScreenRecordingPermission()
            guard screenPermission == .authorized else {
                statusText = "Screen recording permission denied"
                return
            }

            if includeCamera {
                let cameraPermission = await permissionManager.requestCameraPermission()
                guard cameraPermission == .authorized else {
                    statusText = "Camera permission denied"
                    return
                }
            }

            if includeMicrophone {
                let micPermission = await permissionManager.requestMicrophonePermission()
                guard micPermission == .authorized else {
                    statusText = "Microphone permission denied"
                    return
                }
            }

            statusText = "Starting recording..."

            // Create output URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings")
            try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let outputURL = recordingsPath.appendingPathComponent("recording_\(timestamp).mov")

            // Create screen capture configuration
            let sourceSelector = SourceSelector.shared
            let displays = try await sourceSelector.listDisplays()
            guard let display = displays.first else {
                statusText = "No displays found"
                return
            }

            let screenConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: display,
                window: nil,
                application: nil,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32ARGB
            )

            // Create camera configuration if needed
            var cameraConfig: CameraEngine.CameraConfiguration?
            if includeCamera {
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
                captureMicAudio: includeMicrophone
            )

            // Start recording
            let recorder = Recorder.shared
            recordingSession = try await recorder.startRecording(
                config: config,
                outputURL: outputURL
            )

            // Start timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.updateElapsedTime()
                }
            }

            statusText = "Recording..."
            isRecording = true

        } catch {
            statusText = "Error: \(error.localizedDescription)"
            print("❌ Failed to start recording: \(error)")
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

            statusText = "Saved: \(result.screenVideoPath.lastPathComponent)"
            print("✅ Recording saved to: \(result.screenVideoPath)")
            print("   Duration: \(result.duration)s")
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
    }

    func pauseResumeRecording() async {
        guard isRecording, let session = recordingSession else { return }

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
}

/// Shared state manager for recording controls
class RecordingStateManager: ObservableObject {
    static let shared = RecordingStateManager()
    @Published var viewModel: RecordingControlViewModel?
    private init() {}
}

/// Status bar menu with enhanced status display and keyboard shortcuts
class StatusBarMenu {
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?

    init() {
        if isRunningTests {
            return
        }
        setupStatusBar()
        setupStatusUpdateTimer()
    }

    deinit {
        updateTimer?.invalidate()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        Task { @MainActor in
            updateStatus()
        }
    }

    private func setupStatusUpdateTimer() {
        // Update status bar every second to reflect recording state
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil
    }

    @MainActor
    private func updateStatus() {
        guard let button = statusItem?.button else { return }

        if let viewModel = RecordingStateManager.shared.viewModel {
            if viewModel.isRecording {
                // Show recording indicator with time
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                button.title = " \(viewModel.elapsedTime)"
            } else if viewModel.isPaused {
                // Show paused indicator
                button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
                button.title = " Paused"
            } else {
                // Show ready state
                button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Ready")
                button.title = ""
            }
        }
    }

    @objc private func statusBarButtonClicked() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        // Recording status section
        Task { @MainActor in
            if let viewModel = RecordingStateManager.shared.viewModel {
                let statusItem = NSMenuItem(title: viewModel.statusText, action: nil, keyEquivalent: "")
                statusItem.isEnabled = false
                menu.addItem(statusItem)

                if viewModel.isRecording {
                    let timeItem = NSMenuItem(title: "Elapsed: \(viewModel.elapsedTime)", action: nil, keyEquivalent: "")
                    timeItem.isEnabled = false
                    menu.addItem(timeItem)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Recording controls with keyboard shortcuts
        let startItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: "r"
        )
        startItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(startItem)

        let stopItem = NSMenuItem(
            title: "Stop Recording",
            action: #selector(stopRecording),
            keyEquivalent: "\u{1B}" // Escape key
        )
        menu.addItem(stopItem)

        let pauseItem = NSMenuItem(
            title: "Pause/Resume",
            action: #selector(pauseResumeRecording),
            keyEquivalent: " "
        )
        pauseItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle options with keyboard shortcuts
        let cameraItem = NSMenuItem(
            title: "Toggle Camera",
            action: #selector(toggleCamera),
            keyEquivalent: "c"
        )
        cameraItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(cameraItem)

        let micItem = NSMenuItem(
            title: "Toggle Microphone",
            action: #selector(toggleMicrophone),
            keyEquivalent: "m"
        )
        micItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(micItem)

        menu.addItem(NSMenuItem.separator())

        // Show/hide controls
        menu.addItem(NSMenuItem(title: "Show Recording Controls", action: #selector(showRecordingControls), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // App menu
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    @objc private func showRecordingControls() {
        // Bring main window to front
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.title == "CameramanApp" || window.title.isEmpty {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    @objc private func startRecording() {
        Task { @MainActor in
            await RecordingStateManager.shared.viewModel?.startRecording()
            updateStatus()
        }
    }

    @objc private func stopRecording() {
        Task { @MainActor in
            await RecordingStateManager.shared.viewModel?.stopRecording()
            updateStatus()
        }
    }

    @objc private func pauseResumeRecording() {
        Task { @MainActor in
            await RecordingStateManager.shared.viewModel?.pauseResumeRecording()
            updateStatus()
        }
    }

    @objc private func toggleCamera() {
        Task { @MainActor in
            if let viewModel = RecordingStateManager.shared.viewModel {
                viewModel.includeCamera.toggle()
            }
        }
    }

    @objc private func toggleMicrophone() {
        Task { @MainActor in
            if let viewModel = RecordingStateManager.shared.viewModel {
                viewModel.includeMicrophone.toggle()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
