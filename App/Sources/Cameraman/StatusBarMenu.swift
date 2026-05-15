//
//  StatusBarMenu.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import AppKit

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
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
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

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates(userInitiated: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
