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

    init(project: Project, projectDirectory: URL, mutedTracks: Set<TimelineTrackKind> = [], onExportComplete: @escaping (URL?) -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.projectDirectory = projectDirectory
        self.onExportComplete = onExportComplete
        self.onCancel = onCancel
        _viewModel = StateObject(wrappedValue: ExportViewModel(project: project, projectDirectory: projectDirectory, mutedTracks: mutedTracks))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.exportState == .notStarted {
                configurationContent
            } else {
                progressContent
            }
        }
        .frame(width: 560, height: 400)
        .onAppear {
            viewModel.setupExportEngine()
        }
        .onChange(of: viewModel.showSavePanel) { _, shouldShow in
            if shouldShow {
                viewModel.saveExportToFile()
            }
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
                        onCancel()
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

                Picker("Preset", selection: $viewModel.selectedPreset) {
                    ForEach(ExportViewModel.availablePresets, id: \.id) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Destination")
                    .font(.headline)

                HStack(spacing: 12) {
                    TextField("Output Filename", text: $viewModel.outputFilename)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        viewModel.showFilePicker = true
                    }
                    .buttonStyle(.bordered)
                }

                Text("Save to: \(viewModel.outputURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack {
                Spacer()

                Text("Estimated size: \(viewModel.estimatedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Export") {
                    Task {
                        await viewModel.startExport()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExport)
            }
        }
        .padding(20)
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.outputURL = url.appendingPathComponent(viewModel.outputFilename)
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
                Button("Play Video (Temporary)") {
                    print("🎬 [ExportView] Opening temporary file: \(tempURL.path)")
                    NSWorkspace.shared.open(tempURL)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Export Complete", isPresented: $viewModel.showSuccessAlert) {
            Button("OK") {
                dismiss()
                onExportComplete(viewModel.exportResult)
            }
            Button("Reveal in Finder") {
                if let url = viewModel.exportResult {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } message: {
            Text("Your video has been exported successfully!")
        }
    }
}

