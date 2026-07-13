//
//  VoiceoverPanelView.swift
//  App
//
//  Floating panel for recording voiceover narration.
//  Shown as an overlay near the timeline when recording is active.
//

import SwiftUI
import EngineKit

struct VoiceoverPanelView: View {
    @ObservedObject var viewModel: VoiceoverRecordingViewModel
    var playheadTime: TimeInterval
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            if viewModel.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.8)
                    .shadow(color: .red.opacity(0.5), radius: 4)
                    .accessibilityLabel("Recording")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isRecording ? "Recording Voiceover" : "Voiceover Ready")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(viewModel.formattedElapsedTime)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.isRecording ? .red : .secondary)
            }

            Spacer()

            if viewModel.isRecording {
                Button {
                    Task { await viewModel.cancelRecording() }
                    onDismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button {
                    Task {
                        if await viewModel.stopRecording(at: playheadTime) {
                            onDismiss()
                        }
                    }
                } label: {
                    Label("Stop & Insert", systemImage: "stop.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    Label("Record", systemImage: "mic.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .frame(width: 340)
        .overlay(
            Group {
                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(4)
                        .transition(.opacity)
                }
            },
            alignment: .bottom
        )
    }
}
