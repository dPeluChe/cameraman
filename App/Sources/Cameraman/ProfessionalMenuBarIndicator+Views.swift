//
//  ProfessionalMenuBarIndicator+Views.swift
//  Cameraman
//
//  Extracted from ProfessionalMenuBarIndicator.swift
//  Floating recording indicator view
//

import SwiftUI
import EngineKit

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
                recordingIndicator

                Text(menuBarManager.elapsedTime)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)

                Spacer()

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))

                shortcutRow(icon: "stop.circle", text: "Stop", shortcut: "Esc")
                shortcutRow(icon: menuBarManager.isPaused ? "play.circle" : "pause.circle", text: menuBarManager.isPaused ? "Resume" : "Pause", shortcut: "Shift+Cmd Space")
                shortcutRow(icon: "video.slash", text: "Toggle Camera", shortcut: "Shift+Cmd C")
                shortcutRow(icon: "mic.slash", text: "Toggle Mic", shortcut: "Shift+Cmd M")
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
