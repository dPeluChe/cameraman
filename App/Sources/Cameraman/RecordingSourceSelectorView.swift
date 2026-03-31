//
//  RecordingSourceSelectorView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-C — Recording UI (Mejoras)
//

import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI
import EngineKit

/// Visual source selector for recording (display/window/app)
struct RecordingSourceSelectorView: View {
    @StateObject private var viewModel = SourceSelectorViewModel()
    @Binding var selectedSource: CaptureSource
    @Environment(\.openWindow) private var openWindow

    init(selectedSource: Binding<CaptureSource>) {
        self._selectedSource = selectedSource
    }

    enum CaptureSource {
        case display(SourceSelector.DisplaySource)
        case window(SourceSelector.WindowSource)
        case application(SourceSelector.ApplicationSource)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Select Recording Source")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    openMainWindow()
                } label: {
                    Label("Projects", systemImage: "rectangle.stack")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            // Source type tabs
            Picker("Source Type", selection: $viewModel.selectedTab) {
                Text("Display").tag(SourceSelectorViewModel.SourceTab.display)
                Text("Window").tag(SourceSelectorViewModel.SourceTab.window)
                Text("Application").tag(SourceSelectorViewModel.SourceTab.application)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTab) { newTab in
                Task {
                    await viewModel.loadSources(for: newTab)
                }
            }

            // Source list
            ScrollView {
                LazyVStack(spacing: 8) {
                    switch viewModel.selectedTab {
                    case .display:
                        ForEach(viewModel.displaySources) { source in
                            DisplaySourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectDisplay(source) },
                                onPreview: { showPreview(for: source) }
                            )
                        }
                    case .window:
                        ForEach(viewModel.windowSources) { source in
                            WindowSourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectWindow(source) },
                                onPreview: { showPreview(for: source) }
                            )
                        }
                    case .application:
                        ForEach(viewModel.applicationSources) { source in
                            ApplicationSourceRow(
                                source: source,
                                isSelected: isSelected(source),
                                onTap: { selectApplication(source) }
                            )
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Preview section
            if viewModel.previewImage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    if let image = viewModel.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 150)
                            .cornerRadius(8)
                            .background(Color.black.opacity(0.3))
                    }
                }
            }

            // Error or Permission message
            if viewModel.permissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text("Permission Required")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Cameraman needs screen recording permission to capture your screen and windows.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Open System Settings") {
                        Task {
                            await viewModel.openSystemSettings()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Check Again") {
                        Task {
                            await viewModel.loadSources(for: viewModel.selectedTab)
                        }
                    }
                    .buttonStyle(.link)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
            } else if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .onAppear {
            Task {
                await viewModel.loadSources(for: .display)
            }
        }
    }

    // MARK: - Selection Helpers

    private func isSelected(_ source: SourceSelector.DisplaySource) -> Bool {
        if case .display(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func isSelected(_ source: SourceSelector.WindowSource) -> Bool {
        if case .window(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func isSelected(_ source: SourceSelector.ApplicationSource) -> Bool {
        if case .application(let selected) = selectedSource {
            return selected.id == source.id
        }
        return false
    }

    private func selectDisplay(_ source: SourceSelector.DisplaySource) {
        selectedSource = .display(source)
    }

    private func selectWindow(_ source: SourceSelector.WindowSource) {
        selectedSource = .window(source)
    }

    private func selectApplication(_ source: SourceSelector.ApplicationSource) {
        selectedSource = .application(source)
    }

    private func showPreview(for source: SourceSelector.DisplaySource) {
        Task {
            await viewModel.capturePreview(display: source)
        }
    }

    private func showPreview(for source: SourceSelector.WindowSource) {
        Task {
            await viewModel.capturePreview(window: source)
        }
    }

    private func openMainWindow() {
        openWindow(id: WindowID.mainEditor)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Source Row Views

struct DisplaySourceRow: View {
    let source: SourceSelector.DisplaySource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Display icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 44, height: 30)

                    Image(systemName: "display")
                        .foregroundColor(.blue)
                }

                // Display info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .fontWeight(isSelected ? .semibold : .regular)

                    HStack(spacing: 8) {
                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Text("•")
                            .foregroundColor(.white.opacity(0.4))

                        Text("\(Int(source.refreshRate))Hz")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if source.isMain {
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            Text("Main")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct WindowSourceRow: View {
    let source: SourceSelector.WindowSource
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Window icon
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 36, height: 28)

                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }

                // Window info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fontWeight(isSelected ? .semibold : .regular)

                    HStack(spacing: 8) {
                        Text(source.applicationName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Text("•")
                            .foregroundColor(.white.opacity(0.4))

                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if !source.isOnScreen {
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            Text("Off-screen")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(isSelected ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ApplicationSourceRow: View {
    let source: SourceSelector.ApplicationSource
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // App icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 36, height: 36)

                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }

                // App info
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(source.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

