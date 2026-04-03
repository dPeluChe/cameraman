//
//  PreferencesView+Sections.swift
//  App
//
//  Extracted from PreferencesView.swift
//  Individual preference sections and their view models
//

import SwiftUI
import Combine
import EngineKit

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @AppStorage("autosaveEnabled") private var autosaveEnabled = true
    @AppStorage("autosaveInterval") private var autosaveInterval = 30.0
    @AppStorage("showTooltips") private var showTooltips = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Autosave section
            VStack(alignment: .leading, spacing: 12) {
                Text("Autosave")
                    .font(.headline)

                Toggle("Enable autosave", isOn: $autosaveEnabled)
                    .help("Automatically save projects while editing")

                if autosaveEnabled {
                    HStack {
                        Text("Interval:")
                            .foregroundStyle(.secondary)

                        Slider(value: $autosaveInterval, in: 10...300, step: 10) {
                            Text("Autosave interval")
                        }
                        .frame(width: 150)

                        Text("\(Int(autosaveInterval))s")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.leading, 20)
                    .transition(.opacity)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Interface section
            VStack(alignment: .leading, spacing: 12) {
                Text("Interface")
                    .font(.headline)

                Toggle("Show tooltips", isOn: $showTooltips)
                    .help("Display helpful tooltips for UI elements")

                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                    .help("Check for new versions on launch")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // About section
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.headline)

                HStack {
                    Text("Version:")
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundStyle(.primary)
                }

                HStack {
                    Text("Build:")
                        .foregroundStyle(.secondary)
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        .foregroundStyle(.primary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Hotkeys Preferences

struct HotkeysPreferencesView: View {
    @StateObject private var viewModel = HotkeysPreferencesViewModel()
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with info
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)

                Spacer()

                Button(action: { showInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Hotkeys")
                            .font(.headline)
                        Text("Global keyboard shortcuts allow you to control recording without leaving the application you're working in.")
                            .font(.body)
                        Text("Hotkeys work even when the app is in the background.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(width: 250)
                }
            }

            // Hotkeys status
            HStack {
                Circle()
                    .fill(viewModel.hotkeysEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(viewModel.hotkeysEnabled ? "Hotkeys enabled" : "Hotkeys disabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.toggleHotkeys()
                    }
                }) {
                    Text(viewModel.hotkeysEnabled ? "Disable All" : "Enable All")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Registered hotkeys list
            VStack(alignment: .leading, spacing: 12) {
                Text("Registered Shortcuts")
                    .font(.headline)

                if viewModel.registeredHotkeys.isEmpty {
                    Text("No hotkeys registered")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.registeredHotkeys, id: \.action) { hotkey in
                            HotkeyRow(hotkey: hotkey)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Default hotkeys info
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Shortcuts")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    DefaultHotkeyRow(keyEquivalent: "R", modifiers: "⌘⇧", action: "Start Recording")
                    DefaultHotkeyRow(keyEquivalent: "Esc", modifiers: "", action: "Stop Recording")
                    DefaultHotkeyRow(keyEquivalent: "Space", modifiers: "⌘⇧", action: "Pause/Resume")
                    DefaultHotkeyRow(keyEquivalent: "C", modifiers: "⌘⇧", action: "Toggle Camera")
                    DefaultHotkeyRow(keyEquivalent: "M", modifiers: "⌘⇧", action: "Toggle Microphone")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .task {
            await viewModel.loadHotkeys()
        }
    }
}

// MARK: - Hotkey Row Views

struct HotkeyRow: View {
    let hotkey: HotkeyManager.Hotkey

    var body: some View {
        HStack {
            Image(systemName: iconForAction(hotkey.action))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(hotkey.action.description)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Text(keyEquivalent)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
        }
    }

    private var keyEquivalent: String {
        var result = ""
        if hotkey.modifiers & HotkeyManager.Hotkey.cmdKey != 0 { result += "⌘" }
        if hotkey.modifiers & HotkeyManager.Hotkey.optionKey != 0 { result += "⌥" }
        if hotkey.modifiers & HotkeyManager.Hotkey.controlKey != 0 { result += "⌃" }
        if hotkey.modifiers & HotkeyManager.Hotkey.shiftKey != 0 { result += "⇧" }
        result += keyName
        return result
    }

    private var keyName: String {
        switch hotkey.keyCode {
        case HotkeyManager.Hotkey.returnKey: return "↩"
        case HotkeyManager.Hotkey.escapeKey: return "⎋"
        case HotkeyManager.Hotkey.spaceKey: return "Space"
        case HotkeyManager.Hotkey.aKey...HotkeyManager.Hotkey.zKey:
            let chars = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
            let index = Int(hotkey.keyCode - HotkeyManager.Hotkey.aKey)
            return index < chars.count ? chars[index] : "?"
        default: return "?"
        }
    }

    private func iconForAction(_ action: HotkeyManager.Action) -> String {
        switch action {
        case .startRecording: return "record.circle"
        case .stopRecording: return "stop.circle"
        case .pauseResumeRecording: return "pause.circle"
        case .toggleCamera: return "video"
        case .toggleMicrophone: return "mic"
        }
    }
}

struct DefaultHotkeyRow: View {
    let keyEquivalent: String
    let modifiers: String
    let action: String

    var body: some View {
        HStack {
            Text(action)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                if !modifiers.isEmpty {
                    Text(modifiers)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(keyEquivalent)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Recording Preferences

struct RecordingPreferencesView: View {
    @AppStorage("defaultIncludeCamera") private var defaultIncludeCamera = true
    @AppStorage("defaultIncludeMicrophone") private var defaultIncludeMicrophone = false
    @AppStorage("defaultIncludeSystemAudio") private var defaultIncludeSystemAudio = true
    @AppStorage("recordingFrameRate") private var recordingFrameRate = 60.0
    @AppStorage("cameraResolution") private var cameraResolution = "1080p"

    private let frameRates = [30.0, 60.0, 120.0]
    private let resolutions = ["720p", "1080p", "4K"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Recording Sources")
                    .font(.headline)

                Toggle("Include camera by default", isOn: $defaultIncludeCamera)
                Toggle("Include microphone by default", isOn: $defaultIncludeMicrophone)
                Toggle("Include system audio by default", isOn: $defaultIncludeSystemAudio)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Recording Quality")
                    .font(.headline)

                HStack {
                    Text("Frame rate:")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $recordingFrameRate) {
                        ForEach(frameRates, id: \.self) { rate in
                            Text("\(Int(rate)) fps").tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack {
                    Text("Camera resolution:")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $cameraResolution) {
                        ForEach(resolutions, id: \.self) { res in
                            Text(res).tag(res)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Export Preferences

struct ExportPreferencesView: View {
    @AppStorage("defaultExportPreset") private var defaultExportPreset = "Web 1080p H.264"
    @AppStorage("exportDestination") private var exportDestination = "Movies"
    @AppStorage("revealInFinder") private var revealInFinder = true

    private let exportPresets = ["Web 1080p H.264", "High 1080p HEVC", "Portrait 1080p H.264", "Animated GIF"]
    private let destinations = ["Movies", "Documents", "Desktop"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Export Settings")
                    .font(.headline)

                HStack {
                    Text("Preset:")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $defaultExportPreset) {
                        ForEach(exportPresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .frame(width: 250)
                }

                HStack {
                    Text("Destination:")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $exportDestination) {
                        ForEach(destinations, id: \.self) { dest in
                            Text(dest).tag(dest)
                        }
                    }
                    .frame(width: 250)
                }

                Toggle("Reveal in Finder after export", isOn: $revealInFinder)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Export Information")
                    .font(.headline)

                Text("Export settings can be customized per-project in the Export dialog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("These preferences are used as defaults for new exports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - View Models

@MainActor
class PreferencesViewModel: ObservableObject {
    // Placeholder for future preferences state management
}

@MainActor
class HotkeysPreferencesViewModel: ObservableObject {
    @Published private(set) var hotkeysEnabled = false
    @Published private(set) var registeredHotkeys: [HotkeyManager.Hotkey] = []

    private let hotkeyManager = HotkeyManager.shared

    func loadHotkeys() async {
        hotkeysEnabled = hotkeyManager.getEnabled()
        registeredHotkeys = hotkeyManager.getRegisteredHotkeys()
    }

    func toggleHotkeys() async {
        if hotkeysEnabled {
            hotkeyManager.unregisterAllHotkeys()
            hotkeysEnabled = false
        } else {
            do {
                try hotkeyManager.registerDefaultHotkeys()
                hotkeysEnabled = true
            } catch {
                LogError(.ui, "Failed to register hotkeys: \(error)")
            }
        }
        registeredHotkeys = hotkeyManager.getRegisteredHotkeys()
    }
}
