//
//  RecordingControlView.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI
import EngineKit

/// Recording control UI
struct RecordingControlView: View {
    @StateObject private var viewModel = RecordingControlViewModel()
    @State private var showSourceSelector = true
    @State private var selectedSource: RecordingSourceSelectorView.CaptureSource?

    var body: some View {
        VStack(spacing: 16) {
            if showSourceSelector && !viewModel.isRecording {
                RecordingSourceSelectorView(selectedSource: Binding(
                    get: { selectedSource ?? .display(SourceSelector.DisplaySource(id: "0", name: "Main", width: 1920, height: 1080, refreshRate: 60, isMain: true)) }, // Dummy default for binding
                    set: { newValue in
                        selectedSource = newValue
                        showSourceSelector = false
                        Task {
                            await viewModel.configureSource(newValue)
                        }
                    }
                ))
            } else {
                // Header
                HStack {
                    if viewModel.targetProjectId != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.square.fill.on.square.fill")
                                .foregroundColor(.orange)
                            Text("Record New Take")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("Recording Controls")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()

                    if !viewModel.isRecording {
                        Button("Change Source") {
                            showSourceSelector = true
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal)

                Divider()
                    .background(Color.white.opacity(0.2))

                // Status
                HStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : (viewModel.statusText.contains("denied") ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)

                    Text(viewModel.statusText)
                        .font(.system(size: 12))
                        .foregroundColor(viewModel.statusText.contains("denied") ? .orange : .white)
                        .lineLimit(1)

                    Spacer()

                    // Permission fix button
                    if viewModel.statusText.contains("denied") {
                        Button("Fix") {
                            Task {
                                // Open Privacy & Security settings
                                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    if viewModel.isRecording {
                        Text(viewModel.elapsedTime)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)

                // Controls
                HStack(spacing: 12) {
                    // Record/Stop button
                    Button(action: {
                        if viewModel.isRecording {
                            Task { await viewModel.stopRecording() }
                        } else {
                            Task { await viewModel.startRecording() }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isRecording ? Color.red : Color.green)
                                .frame(width: 50, height: 50)

                            Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSource == nil && !viewModel.isRecording) // Disable if no source selected

                    // Pause/Resume button
                    if viewModel.isRecording {
                        Button(action: {
                            Task { await viewModel.pauseResumeRecording() }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 40, height: 40)

                                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Options
                VStack(spacing: 8) {
                    Toggle("Camera", isOn: $viewModel.includeCamera)
                        .toggleStyle(.switch)
                        .foregroundColor(.white)
                        .font(.system(size: 12))

                    Toggle("Microphone", isOn: $viewModel.includeMicrophone)
                        .toggleStyle(.switch)
                        .foregroundColor(.white)
                        .font(.system(size: 12))

                    Toggle("System Audio", isOn: $viewModel.includeSystemAudio)
                        .toggleStyle(.switch)
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .padding()
        .frame(width: showSourceSelector && !viewModel.isRecording ? 500 : 280, height: showSourceSelector && !viewModel.isRecording ? 450 : 260) // Dynamic size
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            // Share view model with status bar menu
            RecordingStateManager.shared.viewModel = viewModel
        }
    }
}
