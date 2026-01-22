//
//  App.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Combine
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
            
            // Add Recording menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    // Open recording controls window
                    NSApp.sendAction(Selector(("showRecordingControlsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Recording Controls Window (Standalone)
        WindowGroup(id: "recording-controls") {
            RecordingControlView()
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                .onAppear {
                    // Ensure window is properly sized and positioned
                    NSApp.windows.first { $0.title == "recording-controls" }?.center()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(arrayLiteral: "recording-controls")) // Only open on explicit request
    }
}

/// Helper for visual effects
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// App delegate for managing lifecycle and hotkeys
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarMenu: StatusBarMenu?
    var professionalMenuBar: ProfessionalMenuBarManager?
    var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup hotkeys
        setupHotkeys()

        // Create status bar menu (legacy, can be removed later)
        statusBarMenu = StatusBarMenu()

        // Create professional menu bar manager
        professionalMenuBar = ProfessionalMenuBarManager.shared

        // Setup notification observers
        setupNotifications()

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

    private func setupNotifications() {
        // Register notification observers for menu bar actions
        NotificationCenter.default.addObserver(forName: .startRecording, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleHotkeyAction(.startRecording)
            }
        }

        NotificationCenter.default.addObserver(forName: .stopRecording, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleHotkeyAction(.stopRecording)
            }
        }

        NotificationCenter.default.addObserver(forName: .pauseResumeRecording, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleHotkeyAction(.pauseResumeRecording)
            }
        }

        NotificationCenter.default.addObserver(forName: .toggleCamera, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleHotkeyAction(.toggleCamera)
            }
        }

        NotificationCenter.default.addObserver(forName: .toggleMicrophone, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleHotkeyAction(.toggleMicrophone)
            }
        }

        NotificationCenter.default.addObserver(forName: .toggleSystemAudio, object: nil, queue: .main) { [weak self] _ in
            // Handle system audio toggle (no hotkey action for now)
            self?.handleSystemAudioToggle()
        }

        NotificationCenter.default.addObserver(forName: .showRecordingControls, object: nil, queue: .main) { [weak self] _ in
            self?.showRecordingControls()
        }
    }

    private func handleSystemAudioToggle() {
        Task { @MainActor in
            guard let viewModel = RecordingStateManager.shared.viewModel else { return }
            viewModel.includeSystemAudio.toggle()
            professionalMenuBar?.includeSystemAudio = viewModel.includeSystemAudio
        }
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
                    professionalMenuBar?.isRecording = true
                    print("▶️ Started recording via hotkey")
                } else {
                    print("⚠️ Recording already in progress")
                }

            case .stopRecording:
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                    professionalMenuBar?.isRecording = false
                    print("⏹️ Stopped recording via hotkey")
                } else {
                    print("⚠️ No recording in progress")
                }

            case .pauseResumeRecording:
                if viewModel.isRecording {
                    await viewModel.pauseResumeRecording()
                    professionalMenuBar?.isPaused = viewModel.isPaused
                    print(viewModel.isPaused ? "⏸️ Paused recording via hotkey" : "▶️ Resumed recording via hotkey")
                } else {
                    print("⚠️ No recording in progress")
                }

            case .toggleCamera:
                viewModel.includeCamera.toggle()
                professionalMenuBar?.includeCamera = viewModel.includeCamera
                print("📷 Camera toggled: \(viewModel.includeCamera ? "enabled" : "disabled")")

            case .toggleMicrophone:
                viewModel.includeMicrophone.toggle()
                professionalMenuBar?.includeMicrophone = viewModel.includeMicrophone
                print("🎤 Microphone toggled: \(viewModel.includeMicrophone ? "enabled" : "disabled")")
            }
        }
    }

    private func showRecordingControls() {
        // Use SwiftUI environment action via notification/callback bridge if possible,
        // but since we are in AppDelegate, we might need to rely on URL scheme or similar
        // if we want to use openWindow.
        // Alternatively, finding the scene is hard.
        
        // For now, let's post a notification that AppNavigation might listen to,
        // OR rely on the Menu Bar Extra opening it.
        
        // Better: Try to open via NSWorkspace URL if we define a scheme, 
        // OR simply activate the app and let the user click "New Recording".
        
        // Actually, since we added a WindowGroup with id "recording-controls",
        // we can try to open it using the environment from a view context.
        // But AppDelegate doesn't have that.
        
        // Workaround: Send action to the responder chain
        NSApp.sendAction(#selector(AppDelegate.openRecordingWindow), to: nil, from: nil)
    }
    
    @objc func openRecordingWindow() {
        // This selector is targeted by the menu item, but we need to actually open the SwiftUI window.
        // We need a bridge. A common pattern is to have a hidden view in the App struct reacting to this.
        NotificationCenter.default.post(name: .openRecordingWindow, object: nil)
    }
}

extension Notification.Name {
    static let openRecordingWindow = Notification.Name("openRecordingWindow")
}

/// Recording control UI
struct RecordingControlView: View {
    @StateObject private var viewModel = RecordingControlViewModel()
    @State private var showSourceSelector = true
    @State private var selectedSource: RecordingSourceSelectorView.CaptureSource?

    var body: some View {
        VStack(spacing: 16) {
            if showSourceSelector && !viewModel.isRecording {
                RecordingSourceSelectorView(selectedSource: Binding(
                    get: { selectedSource ?? .display(SourceSelector.DisplaySource(id: "0", name: "Main", width: 1920, height: 1080, refreshRate: 60, isMain: true)) }, // Dummy default for binding
                    set: { newValue in
                        selectedSource = newValue
                        showSourceSelector = false
                        Task {
                            await viewModel.configureSource(newValue)
                        }
                    }
                ))
            } else {
                // Header
                HStack {
                    Text("Recording Controls")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    
                    if !viewModel.isRecording {
                        Button("Change Source") {
                            showSourceSelector = true
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal)

                Divider()
                    .background(Color.white.opacity(0.2))

                // Status
                HStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : (viewModel.statusText.contains("denied") ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)

                    Text(viewModel.statusText)
                        .font(.system(size: 12))
                        .foregroundColor(viewModel.statusText.contains("denied") ? .orange : .white)
                        .lineLimit(1)

                    Spacer()
                    
                    // Permission fix button
                    if viewModel.statusText.contains("denied") {
                        Button("Fix") {
                            Task {
                                // Open Privacy & Security settings
                                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

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
                    .disabled(selectedSource == nil && !viewModel.isRecording) // Disable if no source selected

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
        }
        .padding()
        .frame(width: showSourceSelector && !viewModel.isRecording ? 500 : 280, height: showSourceSelector && !viewModel.isRecording ? 450 : 260) // Dynamic size
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            // Share view model with status bar menu
            RecordingStateManager.shared.viewModel = viewModel
        }
    }
}

// MARK: - Recording Indicator Window

/// Floating window that shows "REC" indicator during recording
@MainActor
class RecordingIndicatorWindow: NSObject {
    private var window: NSWindow?
    private var blinkTimer: Timer?
    private var isVisible = true
    
    func show() {
        guard let mainScreen = NSScreen.main else { return }
        
        // Create a small window in the top-right corner
        let windowWidth: CGFloat = 100
        let windowHeight: CGFloat = 40
        let padding: CGFloat = 20
        
        let windowFrame = NSRect(
            x: mainScreen.frame.maxX - windowWidth - padding,
            y: mainScreen.frame.maxY - windowHeight - padding,
            width: windowWidth,
            height: windowHeight
        )
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false
        
        // Create content view with "REC" label
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        
        // Background
        let backgroundBox = NSBox(frame: containerView.bounds)
        backgroundBox.boxType = .custom
        backgroundBox.isTransparent = true
        backgroundBox.fillColor = NSColor.red.withAlphaComponent(0.9)
        backgroundBox.cornerRadius = 8
        containerView.addSubview(backgroundBox)
        
        // "REC" label
        let label = NSTextField(frame: containerView.bounds)
        label.stringValue = "● REC"
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        label.alignment = .center
        containerView.addSubview(label)
        
        window.contentView = containerView
        window.orderFrontRegardless()
        
        self.window = window
        
        // Start blinking animation
        isVisible = true
        blinkTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(handleBlinkTimer(_:)), userInfo: nil, repeats: true)
    }

    @objc private func handleBlinkTimer(_ timer: Timer) {
        isVisible.toggle()
        window?.alphaValue = isVisible ? 1.0 : 0.5
    }
    
    func hide() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        if let window = window {
            window.orderOut(nil)
            window.close()
            self.window = nil
        }
    }
}

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
    @Published var includeMicrophone = false
    @Published var includeSystemAudio = true
    @Published var lastRecordingURL: URL?
    
    private var selectedConfig: CaptureEngine.CaptureConfiguration?

    private var timer: Timer?
    private var recordingSession: Recorder.RecordingSession?
    private var recordingIndicator: RecordingIndicatorWindow?
    
    private func log(_ message: String) {
        if debugLoggingEnabled {
            print("[DEBUG-REC] \(message)")
        }
    }
    
    func configureSource(_ source: RecordingSourceSelectorView.CaptureSource) async {
        // Convert UI selection to CaptureConfiguration
        switch source {
        case .display(let displaySource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .display,
                display: displaySource,
                window: nil,
                application: nil,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
            statusText = "Selected: \(displaySource.name)"
            
        case .window(let windowSource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .window,
                display: nil,
                window: windowSource,
                application: nil,
                captureSystemAudio: includeSystemAudio,
                frameRate: 60,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
            statusText = "Selected: \(windowSource.title)"
            
        case .application(let appSource):
            selectedConfig = CaptureEngine.CaptureConfiguration(
                sourceType: .application,
                display: nil,
                window: nil,
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

            // Recreate config with current system audio setting
            let screenConfig = CaptureEngine.CaptureConfiguration(
                sourceType: config.sourceType,
                display: config.display,
                window: config.window,
                application: config.application,
                captureSystemAudio: includeSystemAudio,
                frameRate: config.frameRate,
                pixelFormat: config.pixelFormat
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

            let library = ProjectLibrary()
            let projectId = try await library.createProject(from: result)
            let projectDirectory = try await library.getProjectDirectory(projectId: projectId)

            // Auto-reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([projectDirectory])

            // Open the editor for the newly created project
            NotificationCenter.default.post(name: .openProject, object: projectId)

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
            Task { [weak self] in
                guard let self else { return }
                await MainActor.run {
                    self.updateStatus()
                }
            }
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
        guard statusItem?.button != nil else { return }

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
