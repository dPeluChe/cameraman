//
//  EnhancedRecordingControlsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI (Mejoras)
//

import SwiftUI
import EngineKit

/// Enhanced recording controls with source selector and indicator
struct EnhancedRecordingControlsView: View {
    @StateObject private var viewModel = EnhancedRecordingViewModel()
    @State private var showSourceSelector = false

    var body: some View {
        ZStack {
            if viewModel.isRecording && !showSourceSelector {
                // Show recording indicator
                RecordingIndicatorView()
                    .environmentObject(createIndicatorViewModel())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
            } else if !viewModel.isRecording {
                // Show recording setup
                recordingSetupView
            }
        }
        .sheet(isPresented: $showSourceSelector) {
            RecordingSourceSelectorView(selectedSource: $viewModel.selectedSource)
        }
    }

    private var recordingSetupView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                Text("New Recording")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            // Source selector button
            Button(action: { showSourceSelector = true }) {
                VStack(spacing: 12) {
                    HStack {
                        sourceIcon
                            .font(.system(size: 24))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(sourceName)
                                .font(.system(size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.white)

                            Text(sourceDetails)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }
            }
            .buttonStyle(.plain)

            // Audio/Video toggles
            VStack(spacing: 12) {
                ToggleRow(
                    icon: "video.fill",
                    title: "Camera",
                    isOn: $viewModel.includeCamera
                )

                ToggleRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    isOn: $viewModel.includeMicrophone
                )

                ToggleRow(
                    icon: "speaker.wave.2.fill",
                    title: "System Audio",
                    isOn: $viewModel.includeSystemAudio
                )
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Start button
            Button(action: {
                Task {
                    await viewModel.startRecording()
                }
            }) {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 20))

                    Text("Start Recording")
                        .font(.system(size: 16))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canStartRecording)

            // Hotkey hints
            VStack(spacing: 6) {
                Text("Keyboard Shortcuts")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))

                HStack(spacing: 16) {
                    hotkeyBadge("⇧⌘R", "Start")

                    hotkeyBadge("⎋", "Stop")

                    hotkeyBadge("⇧⌘Space", "Pause")
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }

    private var sourceIcon: some View {
        Group {
            switch viewModel.selectedSource {
            case .display:
                Image(systemName: "display")
                    .foregroundColor(.blue)
            case .window:
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(.purple)
            case .application:
                Image(systemName: "app.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private var sourceName: String {
        switch viewModel.selectedSource {
        case .display(let source):
            return source.name
        case .window(let source):
            return source.title
        case .application(let source):
            return source.name
        }
    }

    private var sourceDetails: String {
        switch viewModel.selectedSource {
        case .display(let source):
            return "Display • \(source.width)×\(source.height)"
        case .window(let source):
            return "\(source.applicationName) • \(source.width)×\(source.height)"
        case .application(let source):
            return source.bundleIdentifier
        }
    }

    private func hotkeyBadge(_ key: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.15))
                .cornerRadius(4)

            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func createIndicatorViewModel() -> RecordingIndicatorViewModel {
        let indicatorVM = RecordingIndicatorViewModel()
        indicatorVM.isRecording = viewModel.isRecording
        indicatorVM.isPaused = viewModel.isPaused
        indicatorVM.elapsedTime = viewModel.elapsedTime
        indicatorVM.includeCamera = viewModel.includeCamera
        indicatorVM.includeMicrophone = viewModel.includeMicrophone
        indicatorVM.includeSystemAudio = viewModel.includeSystemAudio
        indicatorVM.setSource(description: sourceName)
        return indicatorVM
    }
}

// MARK: - Toggle Row

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: isOn ? icon : "\(icon).slash")
                .font(.system(size: 16))
                .foregroundColor(isOn ? .white : .white.opacity(0.4))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - View Model

@MainActor
class EnhancedRecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime = "00:00"
    @Published var includeCamera = true
    @Published var includeMicrophone = false
    @Published var includeSystemAudio = true
    @Published var selectedSource: RecordingSourceSelectorView.CaptureSource = .display(SourceSelector.DisplaySource(
        id: "main",
        name: "Main Display",
        width: 1920,
        height: 1080,
        refreshRate: 60.0,
        isMain: true
    ))

    var canStartRecording: Bool {
        // At least one source must be selected
        return true
    }

    private var timer: Timer?
    private var startTime: Date?

    func startRecording() async {
        guard !isRecording else { return }

        startTime = Date()
        isRecording = true
        isPaused = false

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }

        // TODO: Integrate with actual recording engine
        print("✅ Starting recording with source: \(selectedSource)")
    }

    func stopRecording() async {
        guard isRecording else { return }

        // Stop timer
        timer?.invalidate()
        timer = nil

        isRecording = false
        isPaused = false
        elapsedTime = "00:00"
        startTime = nil

        // TODO: Integrate with actual recording engine
        print("✅ Stopped recording")
    }

    func pauseResumeRecording() async {
        guard isRecording else { return }

        isPaused.toggle()

        // TODO: Integrate with actual recording engine
        print(isPaused ? "⏸️ Paused recording" : "▶️ Resumed recording")
    }

    private func updateElapsedTime() {
        guard let start = startTime else { return }

        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    EnhancedRecordingControlsView()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.3))
}
