//
//  RecordingIndicatorView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI (Mejoras)
//

import SwiftUI
import EngineKit

/// Floating recording indicator with time, status, controls, and hotkey hints
struct RecordingIndicatorView: View {
    @StateObject private var viewModel = RecordingIndicatorViewModel()
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Main content (always visible)
            mainContent

            // Expanded content (on hover)
            if isHovered {
                expandedContent
            }
        }
        .frame(minWidth: isHovered ? 280 : 180)
        .padding(isHovered ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if viewModel.isPaused {
            return Color.orange.opacity(0.9)
        } else if viewModel.isRecording {
            return Color.red.opacity(0.9)
        } else {
            return Color.gray.opacity(0.9)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 12) {
            // Status indicator and time
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    if viewModel.isRecording && !viewModel.isPaused {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    } else if viewModel.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 12, height: 12)
                    }
                }

                // Elapsed time
                Text(viewModel.elapsedTime)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                // Stop button
                Button(action: {
                    Task { await viewModel.stopRecording() }
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Stop Recording (Escape)")
            }

            // Status indicators (compact)
            if viewModel.isRecording {
                HStack(spacing: 16) {
                    // Microphone status
                    statusIndicator(
                        icon: "mic.fill",
                        isActive: viewModel.includeMicrophone,
                        activeColor: .green
                    )

                    // Camera status
                    statusIndicator(
                        icon: "video.fill",
                        isActive: viewModel.includeCamera,
                        activeColor: .blue
                    )

                    // System audio status
                    statusIndicator(
                        icon: "speaker.wave.2.fill",
                        isActive: viewModel.includeSystemAudio,
                        activeColor: .purple
                    )

                    Spacer()
                }
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.3))

            // Recording info
            VStack(alignment: .leading, spacing: 8) {
                Text("Recording Info")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))

                HStack {
                    Text("Source:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(viewModel.sourceDescription)
                        .font(.caption)
                        .foregroundColor(.white)
                    Spacer()
                }

                if let duration = viewModel.estimatedDuration {
                    HStack {
                        Text("Duration:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
            }

            // Pause/Resume button
            if viewModel.isRecording {
                Button(action: {
                    Task { await viewModel.pauseResumeRecording() }
                }) {
                    HStack {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12))
                        Text(viewModel.isPaused ? "Resume" : "Pause")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            // Hotkey hints
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkeys")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))

                hotkeyHint(icon: "stop.circle", text: "Stop", shortcut: "⎋")
                hotkeyHint(icon: viewModel.isPaused ? "play.circle" : "pause.circle", text: viewModel.isPaused ? "Resume" : "Pause", shortcut: "⇧⌘Space")

                Divider()
                    .background(Color.white.opacity(0.2))

                hotkeyHint(icon: "video.slash", text: "Toggle Camera", shortcut: "⇧⌘C")
                hotkeyHint(icon: "mic.slash", text: "Toggle Mic", shortcut: "⇧⌘M")
            }
        }
    }

    // MARK: - Helper Views

    private func statusIndicator(icon: String, isActive: Bool, activeColor: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isActive ? icon : "\(icon).slash")
                .font(.system(size: 10))
                .foregroundColor(isActive ? activeColor : .white.opacity(0.4))

            Circle()
                .fill(isActive ? activeColor : .white.opacity(0.4))
                .frame(width: 4, height: 4)
        }
    }

    private func hotkeyHint(icon: String, text: String, shortcut: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(shortcut)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.15))
                .cornerRadius(3)
        }
    }
}

// MARK: - View Model

@MainActor
class RecordingIndicatorViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime = "00:00"
    @Published var includeCamera = true
    @Published var includeMicrophone = false
    @Published var includeSystemAudio = true
    @Published var sourceDescription = "Display 1"
    @Published var estimatedDuration: String?

    private var timer: Timer?
    private var startTime: Date?

    // MARK: - Recording Control

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
        estimatedDuration = nil
    }

    func pauseResumeRecording() async {
        guard isRecording else { return }

        if isPaused {
            // Resume
            isPaused = false
            // Note: In a real implementation, you'd handle resuming the recording
        } else {
            // Pause
            isPaused = true
            // Note: In a real implementation, you'd handle pausing the recording
        }
    }

    // MARK: - Private Methods

    private func updateElapsedTime() {
        guard let start = startTime else { return }

        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)

        // Update estimated duration
        estimatedDuration = formatDuration(elapsed)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    // MARK: - Configuration

    func setSource(description: String) {
        sourceDescription = description
    }

    func configure(
        camera: Bool,
        microphone: Bool,
        systemAudio: Bool
    ) {
        includeCamera = camera
        includeMicrophone = microphone
        includeSystemAudio = systemAudio
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Not recording
        RecordingIndicatorView()
            .environmentObject(RecordingIndicatorViewModel())

        // Recording
        RecordingIndicatorView()
            .environmentObject({
                let vm = RecordingIndicatorViewModel()
                vm.isRecording = true
                vm.elapsedTime = "01:23"
                return vm
            }())

        // Paused
        RecordingIndicatorView()
            .environmentObject({
                let vm = RecordingIndicatorViewModel()
                vm.isRecording = true
                vm.isPaused = true
                vm.elapsedTime = "02:45"
                return vm
            }())
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
