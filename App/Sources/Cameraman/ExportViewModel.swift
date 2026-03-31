//
//  ExportViewModel.swift
//  App
//
//  Extracted from ExportView.swift
//  View model for export operations
//

import Combine
import SwiftUI
import EngineKit
import AppKit

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
    @Published var showSavePanel: Bool = false
    @Published var temporaryExportURL: URL? = nil

    // GIF-specific options
    @Published var gifFrameRate: Int = 15
    @Published var gifMaxSize: Int = 800
    @Published var gifLoop: Bool = true

    var isGIFPreset: Bool { selectedPreset.id.contains("gif") }

    private let project: Project
    private let projectDirectory: URL
    private let mutedTracks: Set<TimelineTrackKind>
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

    init(project: Project, projectDirectory: URL, mutedTracks: Set<TimelineTrackKind> = []) {
        self.project = project
        self.projectDirectory = projectDirectory
        self.mutedTracks = mutedTracks
        self.outputFilename = project.name.isEmpty ? "Untitled" : project.name
        self.outputURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func setupExportEngine() {
        // ExportEngine will be initialized when needed
    }

    func startExport() async {
        guard canExport else { return }

        exportState = .preparing
        progress = 0
        progressMessage = "Saving project..."
        exportStartTime = Date()

        do {
            // Save the current project state to disk before exporting
            // so the export reads the latest edits (camera position, mask, etc.)
            let store = ProjectStore()
            try await store.saveProject(project)
            let fileExtension = selectedPreset.id.contains("gif") ? "gif" : "mp4"
            let finalFilename = outputFilename.hasSuffix(".\(fileExtension)")
                ? outputFilename
                : "\(outputFilename).\(fileExtension)"

            let library = ProjectLibrary.shared
            let engine = try await library.getExportEngine()
            self.exportEngine = engine

            progressMessage = "Starting export job..."
            let gifOpts: GIFExportOptions? = isGIFPreset
                ? GIFExportOptions(
                    quality: 0.8,
                    loopCount: gifLoop ? 0 : 1,
                    maxSize: gifMaxSize,
                    frameRate: gifFrameRate,
                    dither: true
                )
                : nil

            let jobId = try await engine.export(
                projectId: project.projectId,
                preset: selectedPreset,
                options: ExportOptions(
                    burnCaptions: false,
                    includeCursorHighlight: !isGIFPreset,
                    outputFilename: finalFilename,
                    gifOptions: gifOpts,
                    applyZoom: true,
                    zoomPlan: nil,
                    audioMuteState: AudioMixBuilder.TrackMuteState(
                        systemAudioMuted: mutedTracks.contains(.systemAudio),
                        micAudioMuted: mutedTracks.contains(.micAudio)
                    ),
                    videoMuteState: VideoMuteState(
                        screenMuted: mutedTracks.contains(.screen),
                        cameraMuted: mutedTracks.contains(.camera)
                    )
                )
            )

            self.exportJobId = jobId
            self.exportState = .exporting

            startProgressMonitoring(jobId: jobId, engine: engine, filename: finalFilename)

        } catch {
            exportState = .failed
            progressMessage = "Export failed: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
        }
    }

    private func startProgressMonitoring(jobId: JobId, engine: ExportEngine, filename: String) {
        print("[ExportViewModel] startProgressMonitoring called with filename: \(filename)")

        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                let jobQueue = await engine.getJobQueue()
                let job = await jobQueue.getJob(jobId: jobId)
                let progress = job?.status.progress ?? 0
                let status = job?.status ?? .queued
                let error = job?.error

                self.progress = progress

                switch status {
                case .queued:
                    self.progressMessage = "Queued..."
                case .running:
                    self.progressMessage = "Exporting video..."
                case .success:
                    let tempPath = self.projectDirectory
                        .appendingPathComponent("renders", isDirectory: true)
                        .appendingPathComponent(filename)

                    print("[ExportViewModel] Export success, temporary path: \(tempPath.path)")
                    self.exportState = .completed
                    self.progress = 1.0
                    self.progressMessage = "Export complete!"
                    self.temporaryExportURL = tempPath
                    self.exportResult = nil

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.showSavePanel = true
                    }

                    self.stopProgressMonitoring()
                case .failed:
                    self.exportState = .failed
                    self.progressMessage = "Export failed: \(error?.message ?? "Unknown error")"
                    self.errorMessage = error?.message
                    self.stopProgressMonitoring()
                case .canceled:
                    self.exportState = .failed
                    self.progressMessage = "Export canceled"
                    self.errorMessage = "Export was canceled"
                    self.stopProgressMonitoring()
                }

                if let error = error {
                    self.exportState = .failed
                    self.progressMessage = "Export failed: \(error.message)"
                    self.errorMessage = error.message
                    self.stopProgressMonitoring()
                }
            }
        }
    }

    private func stopProgressMonitoring() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
    }

    func saveExportToFile() {
        guard let tempURL = temporaryExportURL else {
            errorMessage = "No exported file to save"
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Exported Video"
        savePanel.nameFieldStringValue = outputFilename

        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else {
                return
            }

            let finalDestinationURL = destinationURL.pathExtension.isEmpty
                ? destinationURL.appendingPathExtension("mp4")
                : destinationURL

            do {
                let fileManager = FileManager.default
                try fileManager.copyItem(at: tempURL, to: finalDestinationURL)

                self.exportResult = finalDestinationURL
                self.showSuccessAlert = true
            } catch {
                self.errorMessage = "Failed to save file: \(error.localizedDescription)"
            }
        }
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
