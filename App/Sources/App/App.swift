//
//  App.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI

/// Main app entry point
@main
struct CameramanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - we use a floating panel
        Settings {
            EmptyView()
        }
    }
}

/// App delegate for managing lifecycle and hotkeys
class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?
    var statusBarMenu: StatusBarMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar menu
        statusBarMenu = StatusBarMenu()

        // Create floating panel (hidden by default)
        floatingPanel = FloatingPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate when last window closes (floating panel manages lifecycle)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        floatingPanel?.close()
    }
}

/// Floating recording control panel
class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.title = "Recording Controls"
        self.isFloatingPanel = true
        self.level = .floating
        self.backgroundColor = NSColor.clear
        self.contentView = NSHostingView(rootView: RecordingControlView())

        // Center panel on screen
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let panelFrame = self.frame
            self.setFrameOrigin(
                NSPoint(
                    x: frame.midX - panelFrame.width / 2,
                    y: frame.midY - panelFrame.height / 2
                )
            )
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
                        .font(.system(.monospacedDigit, size: 12))
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

    private var startTime: Date?
    private var timer: Timer?
    private var session: EngineKit.Recorder.RecordingSession?

    func startRecording() async {
        guard !isRecording else { return }

        statusText = "Starting recording..."
        startTime = Date()

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }

        // TODO: Create recording configuration and start
        // This would integrate with Recorder from EngineKit
        statusText = "Recording..."
        isRecording = true
    }

    func stopRecording() async {
        guard isRecording else { return }

        statusText = "Stopping recording..."

        // Stop timer
        timer?.invalidate()
        timer = nil

        // TODO: Stop recording and save result
        isRecording = false
        isPaused = false
        startTime = nil
        statusText = "Recording saved"
        elapsedTime = "00:00"
    }

    func pauseResumeRecording() async {
        guard isRecording else { return }

        if isPaused {
            statusText = "Resuming..."
            isPaused = false
            // TODO: Resume recording
            statusText = "Recording..."
        } else {
            statusText = "Pausing..."
            isPaused = true
            // TODO: Pause recording
            statusText = "Paused"
        }
    }

    private func updateElapsedTime() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Shared state manager for recording controls
class RecordingStateManager: ObservableObject {
    static let shared = RecordingStateManager()
    @Published var viewModel: RecordingControlViewModel?
    private init() {}
}

/// Status bar menu
class StatusBarMenu {
    private var statusItem: NSStatusItem?

    init() {
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
    }

    @objc private func statusBarButtonClicked() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show Recording Controls", action: #selector(showRecordingControls), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "."))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    @objc private func showRecordingControls() {
        // Show floating panel
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.floatingPanel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func startRecording() {
        Task { @MainActor in
            await RecordingStateManager.shared.viewModel?.startRecording()
        }
    }

    @objc private func stopRecording() {
        Task { @MainActor in
            await RecordingStateManager.shared.viewModel?.stopRecording()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
