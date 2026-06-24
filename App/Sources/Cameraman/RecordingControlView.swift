//
//  RecordingControlView.swift
//  App
//
//  Unified recording window: 2-step flow (select source → configure & record).
//

import SwiftUI
import EngineKit

enum WindowID {
    static let mainEditor = "main-editor"
    static let recordingControls = "recording-controls"
}

struct RecordingControlView: View {
    @StateObject private var viewModel = RecordingControlViewModel()
    @StateObject private var sourceViewModel = SourceSelectorViewModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedSource: RecordingSourceSelectorView.CaptureSource?
    @State private var showTeleprompter = false
    @State private var countdownValue: Int? = nil

    private var isSourceSelected: Bool { selectedSource != nil }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)

                if viewModel.isRecording {
                    ScrollView { recordingView.padding(20) }
            } else if !viewModel.allRequiredPermissionsGranted {
                ScrollView { RecordingPermissionsGateView(viewModel: viewModel).padding(20) }
            } else if isSourceSelected {
                ScrollView { configureView.padding(20) }
            } else {
                ScrollView { sourcePickerView.padding(20) }
            }
        }
            // Countdown overlay
            if let count = countdownValue {
                countdownOverlay(count)
            }
        }
        .frame(width: 420, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            RecordingStateManager.shared.viewModel = viewModel
            Task { await viewModel.refreshPermissions() }
            Task { await sourceViewModel.loadSources(for: .display) }
        }
        .onChangeCompat(of: scenePhase) { phase in
            // Re-check when returning from System Settings so granting reflects without manual refresh.
            if phase == .active { Task { await viewModel.refreshPermissions() } }
        }
        .onChangeCompat(of: showTeleprompter) { show in
            if show {
                TeleprompterWindowController.shared.show()
            } else {
                TeleprompterWindowController.shared.hide()
            }
        }
        .onDisappear {
            TeleprompterWindowController.shared.hide()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { _ in
            // Window scene is single-instance: openWindow brings existing to front or recreates it
            openWindow(id: WindowID.mainEditor)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if viewModel.isRecording {
                Label("Recording", systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
            } else if viewModel.targetProjectId != nil {
                Label("Record New Take", systemImage: "plus.square.fill.on.square.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else {
                Label("Recording", systemImage: "record.circle")
                    .font(.headline)
            }

            Spacer()

            Button {
                DiagnosticsWindowController.shared.show()
            } label: {
                Image(systemName: "ladybug")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Report a Bug")

            Button {
                openWindow(id: WindowID.mainEditor)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Projects", systemImage: "rectangle.stack")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Step 1: Source Picker (extracted to RecordingControlView+SourcePicker.swift)

    private var sourcePickerView: some View {
        SourcePickerView(sourceViewModel: sourceViewModel) { source in
            selectSource(source)
        }
    }

    // MARK: - Step 2: Configure & Record

    private var configureView: some View {
        VStack(spacing: 16) {
            // Step indicator
            HStack {
                Text("Step 2")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Text("Configure and record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Selected source summary
            if let source = selectedSource {
                sourceSummary(source)
            }

            // Options
            VStack(spacing: 8) {
                ToggleRow(icon: "video.fill", title: "Camera", isOn: $viewModel.includeCamera, offIcon: "video.slash.fill")
                ToggleRow(icon: "mic.fill", title: "Microphone", isOn: $viewModel.includeMicrophone, offIcon: "mic.slash.fill")
                ToggleRow(icon: "speaker.wave.2.fill", title: "System Audio", isOn: $viewModel.includeSystemAudio, offIcon: "speaker.slash.fill")
                Divider().opacity(0.3)
                ToggleRow(icon: "text.justify.leading", title: "Teleprompter", isOn: $showTeleprompter, offIcon: "text.justify.leading")
                Divider().opacity(0.3)
                qualityRow
                if viewModel.selectedDisplaySource != nil {
                    captureAreaRow
                }
            }
            .sectionCard(padding: Spacing.md)

            // Record button (starts countdown then records)
            Button {
                startCountdown()
            } label: {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 18))
                    Text("Start Recording")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                )
                .foregroundStyle(.white)
                .cornerRadius(Radius.medium)
            }
            .buttonStyle(.plain)
            .disabled(countdownValue != nil)

            // Hotkey hints
            hotkeyHints
        }
        // Camera/mic permission is already guaranteed by the Step 0 gate before this view.
    }

    private func sourceSummary(_ source: RecordingSourceSelectorView.CaptureSource) -> some View {
        HStack(spacing: 12) {
            sourceIcon(source)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(sourceColor(source).opacity(0.15))
                .cornerRadius(Radius.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceName(source))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(sourceDetails(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Change") {
                selectedSource = nil
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .sectionCard(padding: Spacing.md)
    }

    // MARK: - Quality & Area Rows (extracted to RecordingControlView+Configure.swift)

    private var qualityRow: some View {
        RecordingQualityRow(recordingQuality: $viewModel.recordingQuality)
    }

    private var captureAreaRow: some View {
        CaptureAreaRow(
            selectedArea: $viewModel.selectedArea,
            selectedDisplaySource: viewModel.selectedDisplaySource,
            onAreaSelected: { rect in
                viewModel.selectedArea = rect
            }
        )
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(viewModel.isPaused ? 0.4 : 1.0)

                    Text(viewModel.isPaused ? "PAUSED" : "REC")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(viewModel.isPaused ? .orange : .red)

                    Spacer()

                    Text(viewModel.elapsedTime)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                }

                if let source = selectedSource {
                    HStack(spacing: 6) {
                        sourceIcon(source).font(.caption)
                        Text(sourceName(source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .sectionCard()

            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.pauseResumeRecording() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20))
                        Text(viewModel.isPaused ? "Resume" : "Pause")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(Radius.medium)
                }
                .buttonStyle(.plain)

                Button {
                    stopAndCleanup()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                        Text("Stop")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(Radius.medium)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                if viewModel.includeCamera {
                    Label("Camera", systemImage: "video.fill").font(.caption2).foregroundStyle(.green)
                }
                if viewModel.includeMicrophone {
                    Label("Mic", systemImage: "mic.fill").font(.caption2).foregroundStyle(.orange)
                }
                if viewModel.includeSystemAudio {
                    Label("Audio", systemImage: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Hotkey Hints

    private var hotkeyHints: some View {
        HStack(spacing: 12) {
            hotkeyBadge("Shift+Cmd+R", "Start")
            hotkeyBadge("Esc", "Stop")
            hotkeyBadge("Shift+Cmd+Space", "Pause")
        }
        .frame(maxWidth: .infinity)
    }

    private func hotkeyBadge(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(3)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownValue = 3
        Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                countdownValue = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdownValue = nil
            await viewModel.startRecording()
            if showTeleprompter {
                TeleprompterWindowController.shared.viewModel.play()
            }
        }
    }

    private func stopAndCleanup() {
        AreaHighlightController.shared.hide()
        Task {
            await viewModel.stopRecording()
            TeleprompterWindowController.shared.viewModel.pause()
        }
    }

    private func countdownOverlay(_ count: Int) -> some View {
        ZStack {
            Color.black.opacity(0.7)
            VStack(spacing: 8) {
                Text("\(count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Recording starts in...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private func selectSource(_ source: RecordingSourceSelectorView.CaptureSource) {
        selectedSource = source
        AreaHighlightController.shared.hide()
        Task { await viewModel.configureSource(source) }
    }

    private func sourceIcon(_ source: RecordingSourceSelectorView.CaptureSource) -> some View {
        Group {
            switch source {
            case .display: Image(systemName: "display").foregroundStyle(.blue)
            case .window: Image(systemName: "rectangle.on.rectangle").foregroundStyle(.purple)
            case .application: Image(systemName: "app.fill").foregroundStyle(.green)
            }
        }
    }

    private func sourceColor(_ source: RecordingSourceSelectorView.CaptureSource) -> Color {
        switch source {
        case .display: return .blue
        case .window: return .purple
        case .application: return .green
        }
    }

    private func sourceName(_ source: RecordingSourceSelectorView.CaptureSource) -> String {
        switch source {
        case .display(let s): return s.name
        case .window(let s): return s.title
        case .application(let s): return s.name
        }
    }

    private func sourceDetails(_ source: RecordingSourceSelectorView.CaptureSource) -> String {
        switch source {
        case .display(let s):
            var detail = "\(s.width)x\(s.height) \(Int(s.refreshRate))Hz"
            if s.isMain { detail += " Main" }
            return detail
        case .window(let s): return "\(s.applicationName) \(s.width)x\(s.height)"
        case .application(let s): return s.bundleIdentifier
        }
    }
}

// MARK: - Toggle Row

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var offIcon: String?

    var body: some View {
        HStack {
            Image(systemName: isOn ? icon : (offIcon ?? icon))
                .font(.system(size: 14))
                .foregroundStyle(isOn ? .primary : .tertiary)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 13))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
