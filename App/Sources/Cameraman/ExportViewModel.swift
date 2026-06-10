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
    /// Scales the preset's target bitrate (0.6 smaller / 1.0 standard / 1.5 higher)
    @Published var qualityMultiplier: Double = 1.0
    @Published var selectedPreset: ExportPreset = .web1080h264 {
        didSet { refreshOutputURL() }
    }
    @Published var outputFilename: String {
        didSet { refreshOutputURL() }
    }
    @Published private(set) var outputURL: URL
    @Published var showFilePicker: Bool = false
    @Published var exportState: ExportState = .notStarted
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var errorMessage: String? = nil
    @Published var exportResult: URL? = nil
    @Published var showSuccessAlert: Bool = false
    @Published var temporaryExportURL: URL? = nil

    // GIF-specific options
    @Published var gifFrameRate: Int = 15
    @Published var gifMaxSize: Int = 800
    @Published var gifLoop: Bool = true

    var isGIFPreset: Bool { selectedPreset.id.contains("gif") }

    private let project: Project
    private let projectDirectory: URL
    private let mutedTracks: Set<TimelineTrackKind>
    /// Effective zoom plan as computed by the preview player at the moment the
    /// export sheet was opened. Already gated by `showZoom`. We re-filter it
    /// against the project segments at export time as a defensive step.
    private let stagedZoomPlan: ZoomPlanGenerator.ZoomPlan?
    private var exportEngine: ExportEngine?
    private var exportJobId: JobId?
    private var exportStartTime: Date?
    private var progressUpdateTimer: Timer?
    private var outputDirectory: URL

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
        .ultra4kHevc,
        .portrait1080h264,
        .animatedGIF
    ]

    var canExport: Bool {
        !sanitizedOutputBaseName.isEmpty && exportState == .notStarted
    }

    var outputDirectoryDisplayName: String {
        let path = outputDirectory.path
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var resolvedOutputFilename: String {
        "\(sanitizedOutputBaseName).\(fileExtension)"
    }

    /// The extension that will be appended to the user-typed filename. Exposed
    /// to the view so it can render an inline `.mp4` / `.gif` suffix.
    var fileExtensionForDisplay: String { fileExtension }

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
        selectedPreset.estimatedSizeText(
            duration: project.timeline.duration,
            qualityMultiplier: qualityMultiplier
        ) ?? "—"
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

    init(
        project: Project,
        projectDirectory: URL,
        mutedTracks: Set<TimelineTrackKind> = [],
        zoomPlan: ZoomPlanGenerator.ZoomPlan? = nil
    ) {
        self.project = project
        self.projectDirectory = projectDirectory
        self.mutedTracks = mutedTracks
        self.stagedZoomPlan = zoomPlan
        let defaultFilename = project.name.isEmpty ? "Untitled" : project.name
        self.outputFilename = defaultFilename
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        self.outputDirectory = moviesDirectory
        self.outputURL = moviesDirectory.appendingPathComponent(defaultFilename).appendingPathExtension("mp4")
    }

    func setupExportEngine() {
        // ExportEngine will be initialized when needed
    }

    func setOutputDirectory(_ directory: URL) {
        outputDirectory = directory
        refreshOutputURL()
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
            let finalFilename = resolvedOutputFilename

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

            // Re-filter the staged plan against this project's per-segment
            // enabled flags as a defensive step (the caller should have
            // filtered already, but we own the contract here).
            let filtered = stagedZoomPlan?.filtered(byEnabledSegments: project.timeline.segments)
            let exportZoomPlan = (filtered?.hasNoZoom ?? true) ? nil : filtered

            let jobId = try await engine.export(
                projectId: project.projectId,
                preset: selectedPreset,
                options: ExportOptions(
                    burnCaptions: false,
                    includeCursorHighlight: !isGIFPreset,
                    outputFilename: finalFilename,
                    gifOptions: gifOpts,
                    applyZoom: exportZoomPlan != nil,
                    zoomPlan: exportZoomPlan,
                    audioMuteState: AudioMixBuilder.TrackMuteState(
                        systemAudioMuted: mutedTracks.contains(.systemAudio),
                        micAudioMuted: mutedTracks.contains(.micAudio)
                    ),
                    videoMuteState: VideoMuteState(
                        screenMuted: mutedTracks.contains(.screen),
                        cameraMuted: mutedTracks.contains(.camera)
                    ),
                    qualityMultiplier: qualityMultiplier
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
        LogDebug(.export, "[ExportViewModel] startProgressMonitoring called with filename: \(filename)")

        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
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

                    LogInfo(.export, "Export success, temporary path: \(tempPath.path)")
                    self.temporaryExportURL = tempPath
                    self.finalizeExport(tempURL: tempPath)

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

    func revealExportInFinder() {
        guard let exportResult else {
            LogError(.export, "Cannot reveal export: no final export URL")
            return
        }

        // Select the file in Finder — opening the folder URL directly needs a
        // security scope the sandbox doesn't have for arbitrary destinations.
        LogInfo(.export, "Revealing export in Finder: \(exportResult.path)")
        NSWorkspace.shared.activateFileViewerSelecting([exportResult])
    }

    deinit {
        progressUpdateTimer?.invalidate()
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

    private var fileExtension: String {
        selectedPreset.id.contains("gif") ? "gif" : "mp4"
    }

    private var sanitizedOutputBaseName: String {
        let trimmed = outputFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lastPathComponent = (trimmed as NSString).lastPathComponent
        let lowercased = lastPathComponent.lowercased()
        if lowercased.hasSuffix(".mp4") || lowercased.hasSuffix(".gif") {
            return (lastPathComponent as NSString).deletingPathExtension
        }

        return lastPathComponent
    }

    private func refreshOutputURL() {
        guard !sanitizedOutputBaseName.isEmpty else {
            outputURL = outputDirectory
            return
        }

        outputURL = outputDirectory.appendingPathComponent(resolvedOutputFilename)
    }

    private func finalizeExport(tempURL: URL) {
        let destinationURL = outputURL
        LogInfo(.export, "Saving final export from temporary file: \(tempURL.path)")
        LogInfo(.export, "Final export destination: \(destinationURL.path)")

        let didStartAccess = outputDirectory.startAccessingSecurityScopedResource()
        LogInfo(.export, "Security scoped access for export folder: \(didStartAccess ? "granted" : "not required")")

        defer {
            if didStartAccess {
                outputDirectory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            if tempURL.standardizedFileURL != destinationURL.standardizedFileURL {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: tempURL, to: destinationURL)
            }

            exportState = .completed
            progress = 1.0
            progressMessage = "Export complete."
            exportResult = destinationURL
            showSuccessAlert = true
            LogInfo(.export, "Export saved to final destination: \(destinationURL.path)")
        } catch {
            exportState = .failed
            progressMessage = "Export failed while saving file."
            errorMessage = "Failed to save export: \(error.localizedDescription)"
            LogError(.export, "Failed to save final export to \(destinationURL.path): \(error.localizedDescription)")
        }
    }
}
