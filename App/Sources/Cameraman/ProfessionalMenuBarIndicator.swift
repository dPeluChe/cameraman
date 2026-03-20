//
//  ProfessionalMenuBarIndicator.swift
//  Cameraman
//
//  Created by Droid on 2026-01-21.
//  Professional menu bar recording indicator with timer and controls
//

import SwiftUI
import AppKit
import Combine
import EngineKit

/// Professional menu bar manager for recording status
class ProfessionalMenuBarManager: ObservableObject {
    static let shared = ProfessionalMenuBarManager()

    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?

    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var elapsedTime: String = "00:00"
    @Published var includeCamera: Bool = true
    @Published var includeMicrophone: Bool = false
    @Published var includeSystemAudio: Bool = true

    private init() {
        setupStatusBar()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")
            button.image?.isTemplate = true
        }

        updateStatus()
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }

        if isRecording {
            if isPaused {
                button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
                button.title = " Paused"
            } else {
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                button.title = " \(elapsedTime)"
            }
            button.image?.isTemplate = false
        } else {
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Ready")
            button.title = ""
            button.image?.isTemplate = true
        }
    }

    func showMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        // Recording status section
        addStatusSection(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Recording controls
        addRecordingControls(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Options
        addOptions(to: menu)

        menu.addItem(NSMenuItem.separator())

        // App controls
        menu.addItem(NSMenuItem(
            title: "Show Recording Controls",
            action: #selector(showRecordingControls),
            keyEquivalent: "1"
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Cameraman",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func addStatusSection(to menu: NSMenu) {
        if isRecording {
            let statusItem = NSMenuItem(title: isPaused ? "⏸ Paused" : "🔴 Recording", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            let timeItem = NSMenuItem(title: "Time: \(elapsedTime)", action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)

            menu.addItem(NSMenuItem.separator())

            // Add source indicators
            let sourcesItem = NSMenuItem(title: "Capturing:", action: nil, keyEquivalent: "")
            sourcesItem.isEnabled = false
            menu.addItem(sourcesItem)

            addSourceIndicator(to: menu, icon: "display", label: "Screen", enabled: true)

            if includeCamera {
                addSourceIndicator(to: menu, icon: "video", label: "Camera", enabled: true)
            }

            if includeMicrophone {
                addSourceIndicator(to: menu, icon: "mic", label: "Microphone", enabled: true)
            }

            if includeSystemAudio {
                addSourceIndicator(to: menu, icon: "speaker.wave.2", label: "System Audio", enabled: true)
            }
        } else {
            let statusItem = NSMenuItem(title: "○ Ready to record", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }
    }

    private func addSourceIndicator(to menu: NSMenu, icon: String, label: String, enabled: Bool) {
        let item = NSMenuItem(
            title: "  \(enabled ? "✓" : "✗") \(label)",
            action: nil,
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        item.image?.size = NSSize(width: 16, height: 16)
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addRecordingControls(to menu: NSMenu) {
        if isRecording {
            // Stop button
            let stopItem = NSMenuItem(
                title: "⏹ Stop Recording",
                action: #selector(stopRecording),
                keyEquivalent: "\u{1B}" // Escape
            )
            stopItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
            menu.addItem(stopItem)

            // Pause/Resume button
            let pauseItem = NSMenuItem(
                title: isPaused ? "▶ Resume Recording" : "⏸ Pause Recording",
                action: #selector(pauseResumeRecording),
                keyEquivalent: " "
            )
            pauseItem.keyEquivalentModifierMask = [.command, .shift]
            pauseItem.image = NSImage(systemSymbolName: isPaused ? "play.fill" : "pause.fill", accessibilityDescription: "Pause")
            menu.addItem(pauseItem)
        } else {
            // Start button
            let startItem = NSMenuItem(
                title: "▶ Start Recording",
                action: #selector(startRecording),
                keyEquivalent: "r"
            )
            startItem.keyEquivalentModifierMask = [.command, .shift]
            startItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record")
            menu.addItem(startItem)
        }
    }

    private func addOptions(to menu: NSMenu) {
        let cameraItem = NSMenuItem(
            title: includeCamera ? "✓ Camera" : "  Camera",
            action: #selector(toggleCamera),
            keyEquivalent: "c"
        )
        cameraItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(cameraItem)

        let micItem = NSMenuItem(
            title: includeMicrophone ? "✓ Microphone" : "  Microphone",
            action: #selector(toggleMicrophone),
            keyEquivalent: "m"
        )
        micItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(micItem)

        let systemAudioItem = NSMenuItem(
            title: includeSystemAudio ? "✓ System Audio" : "  System Audio",
            action: #selector(toggleSystemAudio),
            keyEquivalent: "s"
        )
        systemAudioItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(systemAudioItem)
    }

    // MARK: - Actions

    @objc private func startRecording() {
        NotificationCenter.default.post(name: .startRecording, object: nil)
    }

    @objc private func stopRecording() {
        NotificationCenter.default.post(name: .stopRecording, object: nil)
    }

    @objc private func pauseResumeRecording() {
        NotificationCenter.default.post(name: .pauseResumeRecording, object: nil)
    }

    @objc private func toggleCamera() {
        includeCamera.toggle()
        NotificationCenter.default.post(name: .toggleCamera, object: nil)
        updateStatus()
    }

    @objc private func toggleMicrophone() {
        includeMicrophone.toggle()
        NotificationCenter.default.post(name: .toggleMicrophone, object: nil)
        updateStatus()
    }

    @objc private func toggleSystemAudio() {
        includeSystemAudio.toggle()
        NotificationCenter.default.post(name: .toggleSystemAudio, object: nil)
        updateStatus()
    }

    @objc private func showRecordingControls() {
        NotificationCenter.default.post(name: .showRecordingControls, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startRecording = Notification.Name("startRecording")
    static let stopRecording = Notification.Name("stopRecording")
    static let pauseResumeRecording = Notification.Name("pauseResumeRecording")
    static let toggleCamera = Notification.Name("toggleCamera")
    static let toggleMicrophone = Notification.Name("toggleMicrophone")
    static let toggleSystemAudio = Notification.Name("toggleSystemAudio")
    static let showRecordingControls = Notification.Name("showRecordingControls")
}

