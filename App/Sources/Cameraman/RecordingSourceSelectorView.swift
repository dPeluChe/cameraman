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
                    .foregroundColor(.primary)
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
            .onChangeCompat(of: viewModel.selectedTab) { newTab in
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

            // Preview section
            if viewModel.previewImage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let image = viewModel.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 150)
                            .cornerRadius(8)
                            .background(AppColor.inset)
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
                        .foregroundColor(.primary)
                    
                    Text("Cameraman needs screen recording permission to capture your screen and windows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                .background(AppColor.inset)
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
        .background(AppColor.panelTranslucent)
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
