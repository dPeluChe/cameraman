//
//  ExportView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit
import UniformTypeIdentifiers

// MARK: - Export View (Modal)

struct ExportView: View {
    let project: Project
    let projectDirectory: URL
    let onExportComplete: (URL?) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(project: Project, projectDirectory: URL, onExportComplete: @escaping (URL?) -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.projectDirectory = projectDirectory
        self.onExportComplete = onExportComplete
        self.onCancel = onCancel
        _viewModel = StateObject(wrappedValue: ExportViewModel(project: project))
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
                Button("Cancel Export") {
                    Task {
                        await viewModel.cancelExport()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.exportState == .completed || viewModel.exportState == .failed)
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
        .onChange(of: viewModel.exportResult) { oldValue, newValue in
            if newValue != nil {
                dismiss()
                onExportComplete(newValue)
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

// MARK: - Export View Model

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var selectedPreset: ExportPreset = .web1080h264
    @Published var outputFilename: String
    @Published var outputURL: URL
    @Published var showFilePicker: Bool = false
    @Published var exportState: ExportState = .notStarted
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var errorMessage: String? = nil
    @Published var exportResult: URL? = nil
    @Published var showSuccessAlert: Bool = false

    private let project: Project
    private var exportEngine: ExportEngine?
    private var exportJobId: JobId?
    private var exportStartTime: Date?
    private var progressUpdateTimer: Timer?

    enum ExportState {
        case notStarted
        case preparing
        case exporting
        case completed
        case failed
    }

    static let availablePresets: [ExportPreset] = [
        .web1080h264,
        .high1080hevc,
        .portrait1080h264,
        .animatedGIF
    ]

    var canExport: Bool {
        !outputFilename.isEmpty && exportState == .notStarted
    }

    var progressPercentage: Int {
        Int(progress * 100)
    }

    var progressColor: Color {
        switch exportState {
        case .notStarted:
            return .secondary
        case .preparing:
            return .orange
        case .exporting:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    var progressTitle: String {
        switch exportState {
        case .notStarted:
            return "Export"
        case .preparing:
            return "Preparing Export..."
        case .exporting:
            return "Exporting..."
        case .completed:
            return "Export Complete!"
        case .failed:
            return "Export Failed"
        }
    }

    var progressDescription: String {
        switch exportState {
        case .notStarted, .preparing:
            return "Starting..."
        case .exporting:
            return "\(progressPercentage)% complete"
        case .completed:
            return "100% - Complete"
        case .failed:
            return "Export failed"
        }
    }

    var estimatedFileSize: String {
        let duration = project.timeline.duration
        let bitrateMbps = selectedPreset.output.bitrateMbps
        let estimatedSizeMB = (duration * bitrateMbps) / 8

        if estimatedSizeMB < 1024 {
            return String(format: "%.1f MB", estimatedSizeMB)
        } else {
            return String(format: "%.2f GB", estimatedSizeMB / 1024)
        }
    }

    var estimatedTimeRemaining: String? {
        guard let startTime = exportStartTime,
              exportState == .exporting,
              progress > 0.01 else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed

        if remaining < 60 {
            return "\(Int(remaining))s remaining"
        } else {
            return "\(Int(remaining / 60))m \(Int(remaining.truncatingRemainder(dividingBy: 60)))s remaining"
        }
    }

    init(project: Project) {
        self.project = project
        self.outputFilename = project.name.isEmpty ? "Untitled" : project.name
        self.outputURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func setupExportEngine() {
        // ExportEngine will be initialized when needed
        // For now, we'll use ProjectLibrary to get the engine
    }

    func startExport() async {
        guard canExport else { return }

        exportState = .preparing
        progress = 0
        progressMessage = "Initializing export..."
        exportStartTime = Date()

        do {
            // Add file extension based on preset
            let fileExtension = selectedPreset.id.contains("gif") ? "gif" : "mp4"
            let finalFilename = outputFilename.hasSuffix(".\(fileExtension)")
                ? outputFilename
                : "\(outputFilename).\(fileExtension)"
            let finalURL = outputURL.deletingLastPathComponent().appendingPathComponent(finalFilename)

            // Initialize export engine
            let library = ProjectLibrary()
            let engine = try await library.getExportEngine()
            self.exportEngine = engine

            // Start export
            progressMessage = "Starting export job..."
            let jobId = try await engine.export(
                projectId: project.id,
                preset: selectedPreset,
                options: ExportOptions(
                    burnCaptions: false,
                    includeCursorHighlight: true,
                    outputFilename: finalFilename,
                    gifOptions: nil,
                    applyZoom: true,
                    zoomPlan: nil
                )
            )

            self.exportJobId = jobId
            self.exportState = .exporting

            // Start progress monitoring
            startProgressMonitoring(jobId: jobId, engine: engine, outputURL: finalURL)

        } catch {
            exportState = .failed
            progressMessage = "Export failed: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
        }
    }

    private func startProgressMonitoring(jobId: JobId, engine: ExportEngine, outputURL: URL) {
        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                let jobQueue = await engine.getJobQueue()
                let job = await jobQueue.getJob(id: jobId)
                let progress = job?.progress ?? 0
                let status = job?.status ?? .pending
                let error = job?.error

                self.progress = progress

                switch status {
                case .pending:
                    self.progressMessage = "Queued..."
                case .inProgress:
                    self.progressMessage = "Exporting video..."
                case .completed:
                    self.exportState = .completed
                    self.progress = 1.0
                    self.progressMessage = "Export complete!"
                    self.exportResult = outputURL
                    self.showSuccessAlert = true
                    self.stopProgressMonitoring()
                case .failed(let jobError):
                    self.exportState = .failed
                    self.progressMessage = "Export failed: \(jobError?.localizedDescription ?? "Unknown error")"
                    self.errorMessage = jobError?.localizedDescription
                    self.stopProgressMonitoring()
                }

                if let error = error {
                    self.exportState = .failed
                    self.progressMessage = "Export failed: \(error.localizedDescription)"
                    self.errorMessage = error.localizedDescription
                    self.stopProgressMonitoring()
                }
            }
        }
    }

    private func stopProgressMonitoring() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
    }

    func cancelExport() async {
        guard let jobId = exportJobId,
              let engine = exportEngine else {
            return
        }

        do {
            try await engine.cancelExport(jobId: jobId)
            exportState = .notStarted
            progress = 0
            progressMessage = ""
            stopProgressMonitoring()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    ExportView(
        project: Project(
            name: "Test Project",
            canvas: CanvasLayout(),
            timeline: Project.Timeline(segments: []),
            sources: Project.Sources(),
            createdAt: Date(),
            updatedAt: Date()
        ),
        projectDirectory: FileManager.default.temporaryDirectory,
        onExportComplete: { url in
            print("Export complete: \(url?.path ?? "none")")
        },
        onCancel: {
            print("Export cancelled")
        }
    )
}
