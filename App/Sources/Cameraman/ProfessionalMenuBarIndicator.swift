//
//  ProfessionalMenuBarIndicator.swift
//  Cameraman
//
//  Created by Droid on 2026-01-21.
//  Professional menu bar recording indicator with timer and controls
//

import SwiftUI
import AppKit
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

// MARK: - Floating Recording Indicator View

struct ProfessionalRecordingIndicatorView: View {
    @StateObject private var menuBarManager = ProfessionalMenuBarManager.shared
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact mode (always visible)
            compactView

            // Expanded view (on hover)
            if isHovered {
                expandedView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: isHovered ? 320 : 200)
        .padding(isHovered ? 20 : 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundMaterial)
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundMaterial: some ShapeStyle {
        if menuBarManager.isPaused {
            return Color.orange.opacity(0.95)
        } else if menuBarManager.isRecording {
            return Color.red.opacity(0.95)
        } else {
            return Color.gray.opacity(0.9)
        }
    }

    private var compactView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Recording indicator
                recordingIndicator

                // Time
                Text(menuBarManager.elapsedTime)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)

                Spacer()

                // Stop button
                Button(action: {
                    NotificationCenter.default.post(name: .stopRecording, object: nil)
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .help("Stop Recording (Esc)")
            }

            // Source indicators
            if menuBarManager.isRecording {
                HStack(spacing: 16) {
                    sourceIndicator(icon: "mic.fill", isActive: menuBarManager.includeMicrophone, color: .green)
                    sourceIndicator(icon: "video.fill", isActive: menuBarManager.includeCamera, color: .blue)
                    sourceIndicator(icon: "speaker.wave.2.fill", isActive: menuBarManager.includeSystemAudio, color: .purple)

                    Spacer()
                }
            }
        }
    }

    private var expandedView: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.3))

            // Recording info
            VStack(alignment: .leading, spacing: 10) {
                Text("Recording Info")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))

                infoRow(icon: "display", label: "Screen")
                if menuBarManager.includeCamera {
                    infoRow(icon: "video", label: "Camera")
                }
                if menuBarManager.includeMicrophone {
                    infoRow(icon: "mic", label: "Microphone")
                }
                if menuBarManager.includeSystemAudio {
                    infoRow(icon: "speaker.wave.2", label: "System Audio")
                }
            }

            // Pause/Resume
            if menuBarManager.isRecording {
                Button(action: {
                    NotificationCenter.default.post(name: .pauseResumeRecording, object: nil)
                }) {
                    HStack {
                        Image(systemName: menuBarManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14))
                        Text(menuBarManager.isPaused ? "Resume Recording" : "Pause Recording")
                            .font(.system(size: 13))
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // Keyboard shortcuts
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))

                shortcutRow(icon: "stop.circle", text: "Stop", shortcut: "⎋ Esc")
                shortcutRow(icon: menuBarManager.isPaused ? "play.circle" : "pause.circle", text: menuBarManager.isPaused ? "Resume" : "Pause", shortcut: "⇧⌘ Space")
                shortcutRow(icon: "video.slash", text: "Toggle Camera", shortcut: "⇧⌘ C")
                shortcutRow(icon: "mic.slash", text: "Toggle Mic", shortcut: "⇧⌘ M")
            }
        }
    }

    private var recordingIndicator: some View {
        ZStack {
            if menuBarManager.isRecording && !menuBarManager.isPaused {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)

                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.3), radius: 3)
            } else if menuBarManager.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func sourceIndicator(icon: String, isActive: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? icon : "\(icon).slash")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? color : .white.opacity(0.5))

            Circle()
                .fill(isActive ? color : .white.opacity(0.5))
                .frame(width: 5, height: 5)
        }
    }

    private func infoRow(icon: String, label: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        }
    }

    private func shortcutRow(icon: String, text: String, shortcut: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text(shortcut)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.15))
                .cornerRadius(4)
        }
    }
}

// MARK: - Preview

#Preview("Recording") {
    ProfessionalRecordingIndicatorView()
        .environmentObject({
            let manager = ProfessionalMenuBarManager.shared
            manager.isRecording = true
            manager.elapsedTime = "01:34"
            return manager
        }())
}

#Preview("Paused") {
    ProfessionalRecordingIndicatorView()
        .environmentObject({
            let manager = ProfessionalMenuBarManager.shared
            manager.isRecording = true
            manager.isPaused = true
            manager.elapsedTime = "02:15"
            return manager
        }())
}

#Preview("Ready") {
    ProfessionalRecordingIndicatorView()
        .environmentObject(ProfessionalMenuBarManager.shared)
}
