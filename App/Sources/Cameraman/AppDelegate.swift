//
//  AppDelegate.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AppKit
import EngineKit

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
            LogInfo(.ui, "Default hotkeys registered successfully")
        } catch {
            LogError(.ui, "Failed to register hotkeys: \(error.localizedDescription)")
        }
    }

    private func handleHotkeyAction(_ action: HotkeyManager.Action) {
        Task { @MainActor in
            guard let viewModel = RecordingStateManager.shared.viewModel else {
                LogWarning(.ui, "Recording view model not available for hotkey")
                return
            }

            switch action {
            case .startRecording:
                if !viewModel.isRecording {
                    await viewModel.startRecording()
                    professionalMenuBar?.isRecording = true
                    LogInfo(.capture, "Started recording via hotkey")
                } else {
                    LogWarning(.capture, "Recording already in progress")
                }

            case .stopRecording:
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                    professionalMenuBar?.isRecording = false
                    LogInfo(.capture, "Stopped recording via hotkey")
                } else {
                    LogWarning(.capture, "No recording in progress")
                }

            case .pauseResumeRecording:
                if viewModel.isRecording {
                    await viewModel.pauseResumeRecording()
                    professionalMenuBar?.isPaused = viewModel.isPaused
                    LogInfo(.capture, viewModel.isPaused ? "Paused recording via hotkey" : "Resumed recording via hotkey")
                } else {
                    LogWarning(.capture, "No recording in progress")
                }

            case .toggleCamera:
                viewModel.includeCamera.toggle()
                professionalMenuBar?.includeCamera = viewModel.includeCamera
                LogDebug(.capture, "Camera toggled: \(viewModel.includeCamera ? "enabled" : "disabled")")

            case .toggleMicrophone:
                viewModel.includeMicrophone.toggle()
                professionalMenuBar?.includeMicrophone = viewModel.includeMicrophone
                LogDebug(.capture, "Microphone toggled: \(viewModel.includeMicrophone ? "enabled" : "disabled")")
            }
        }
    }

    private func showRecordingControls() {
        // Workaround: Send action to the responder chain
        NSApp.sendAction(#selector(AppDelegate.openRecordingWindow), to: nil, from: nil)
    }

    @objc func openRecordingWindow() {
        // This selector is targeted by the menu item, but we need to actually open the SwiftUI window.
        // We need a bridge. A common pattern is to have a hidden view in the App struct reacting to this.
        NotificationCenter.default.post(name: .openRecordingWindow, object: nil)
    }
}
