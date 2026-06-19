//
//  ExportView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import Combine
import SwiftUI
import EngineKit
import UniformTypeIdentifiers
import AppKit

// MARK: - Export View (Modal)

struct ExportView: View {
    let project: Project
    let projectDirectory: URL
    let onExportComplete: (URL?) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        project: Project,
        projectDirectory: URL,
        mutedTracks: Set<TimelineTrackKind> = [],
        zoomPlan: ZoomPlanGenerator.ZoomPlan? = nil,
        onExportComplete: @escaping (URL?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.project = project
        self.projectDirectory = projectDirectory
        self.onExportComplete = onExportComplete
        self.onCancel = onCancel
        _viewModel = StateObject(wrappedValue: ExportViewModel(
            project: project,
            projectDirectory: projectDirectory,
            mutedTracks: mutedTracks,
            zoomPlan: zoomPlan
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                if viewModel.exportState == .notStarted {
                    configurationContent
                } else {
                    progressContent
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 560, maxWidth: 680, minHeight: 360, idealHeight: 440, maxHeight: 640)
        .onAppear {
            viewModel.setupExportEngine()
        }
    }

    private var header: some View {
        HStack {
            Text("Export Video")
                .font(.headline)

            Spacer()

            if viewModel.exportState == .notStarted {
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .buttonStyle(.bordered)
            } else {
                if viewModel.exportState == .completed || viewModel.exportState == .failed {
                    Button("Done") {
                        dismiss()
                        if viewModel.exportState == .completed {
                            onExportComplete(viewModel.exportResult)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Cancel Export") {
                        Task {
                            await viewModel.cancelExport()
                            dismiss()
                            onCancel()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Configuration Content

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preset")
                    .font(.headline)

                presetPicker
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // GIF-specific options
            if viewModel.isGIFPreset {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("GIF Options")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Frame Rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("FPS", selection: $viewModel.gifFrameRate) {
                                Text("10 fps").tag(10)
                                Text("15 fps").tag(15)
                                Text("24 fps").tag(24)
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Size", selection: $viewModel.gifMaxSize) {
                                Text("Small (480)").tag(480)
                                Text("Medium (800)").tag(800)
                                Text("Large (1200)").tag(1200)
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle("Loop", isOn: $viewModel.gifLoop)
                            .toggleStyle(.switch)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Filename")
                    .font(.headline)

                HStack(spacing: 0) {
                    TextField("Export filename", text: $viewModel.outputFilename)
                        .textFieldStyle(.roundedBorder)

                    Text(".\(viewModel.fileExtensionForDisplay)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                        .monospacedDigit()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Destination")
                    .font(.headline)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        destinationFolderText

                        Spacer()

                        chooseLocationButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        destinationFolderText
                        chooseLocationButton
                    }
                }

                Text(viewModel.outputURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            ViewThatFits(in: .horizontal) {
                HStack {
                    Spacer()

                    estimatedSizeText
                    exportButton
                }

                VStack(alignment: .trailing, spacing: 8) {
                    estimatedSizeText
                    exportButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.setOutputDirectory(url)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert("Export Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private var presetPicker: some View {
        Picker("Preset", selection: $viewModel.selectedPreset) {
            ForEach(ExportViewModel.availablePresets, id: \.id) { preset in
                Text(preset.name).tag(preset)
            }
        }
    }

    private var destinationFolderText: some View {
        Text(viewModel.outputDirectoryDisplayName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var chooseLocationButton: some View {
        Button("Choose Location...") {
            viewModel.showFilePicker = true
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var estimatedSizeText: some View {
        // GIF has no target bitrate, so neither control applies there
        if !viewModel.isGIFPreset {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Quality", selection: $viewModel.qualityMultiplier) {
                    Text("Smaller file").tag(0.6)
                    Text("Standard").tag(1.0)
                    Text("Higher quality").tag(1.5)
                }
                .pickerStyle(.segmented)
                .help("Scales the preset's target bitrate — the estimate updates accordingly")

                Text("Estimated size: \(viewModel.estimatedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportButton: some View {
        Button("Export") {
            Task {
                await viewModel.startExport()
            }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction) // ⌘↵ triggers Export in the dialog
        .disabled(!viewModel.canExport)
    }

    // MARK: - Progress Content

    private var progressContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(viewModel.progressColor)

                Text(viewModel.progressTitle)
                    .font(.title2)
                    .fontWeight(.medium)

                Text(viewModel.progressMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ProgressView(value: viewModel.progress)

                HStack {
                    Text("\(viewModel.progressPercentage)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Text(viewModel.progressDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)

            if let estimatedTime = viewModel.estimatedTimeRemaining {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text("Estimated time: \(estimatedTime)")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if let tempURL = viewModel.temporaryExportURL, viewModel.exportState == .completed {
                HStack(spacing: 10) {
                    Button("Show in Finder") {
                        viewModel.revealExportInFinder()
                    }
                    .buttonStyle(.bordered)

                    Button("Play Video") {
                        LogDebug(.export, "Opening exported file: \(viewModel.exportResult?.path ?? tempURL.path)")
                        NSWorkspace.shared.open(viewModel.exportResult ?? tempURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
