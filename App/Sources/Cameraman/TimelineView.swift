//
//  TimelineView.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//

import SwiftUI
import EngineKit
import CoreGraphics
import AVFoundation
import UniformTypeIdentifiers

struct TimelineView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    let projectDirectory: URL?
    @Binding var mutedTracks: Set<TimelineTrackKind>
    @Binding var selectedSegmentId: String?
    @Binding var selectedMediaItemId: UUID?
    @Binding var selectedOverlayId: UUID?

    private let trackHeight: TimelineScalar = 34
    private let trackSpacing: TimelineScalar = 8
    private let pixelsPerSecond: TimelineScalar = 40
    private let labelWidth: TimelineScalar = 160
    private let minZoomScale: TimelineScalar = 0.5
    private let maxZoomScale: TimelineScalar = 4
    private let zoomStep: TimelineScalar = 0.25
    private let minimumTrimDuration: TimeInterval = 0.1

    @State private var zoomScale: TimelineScalar = 1
    @State private var availableWidth: CGFloat = 800
    @State private var selection: RangeSelection?
    @State private var dragStartTime: TimeInterval?
    @State private var isTrimming = false
    @State private var showImportPanel = false
    @State private var zoomSuggestions: [ZoomSuggestion] = []
    @State private var dismissedSuggestionIds: Set<UUID> = []
    @State private var isGeneratingSuggestions = false
    @State private var thumbnailTask: Task<Void, Never>?

    // Thumbnail cache
    @State private var thumbnailCache: ThumbnailCache?
    @State private var thumbnails: [TimeInterval: NSImage] = [:]
    @State private var showThumbnails: Bool = true

    // Waveform cache
    @State private var waveforms: [String: [Float]] = [:]
    @State private var showWaveforms: Bool = true

    private var project: Project { editor.project }

    // Convenience accessor for playhead time
    private var playheadTime: Double { playerViewModel.currentTime }

    // MARK: - Thumbnail Management

    private func initializeThumbnailCache(projectDirectory: String) {
        thumbnailTask?.cancel()
        let cache = ThumbnailCache(configuration: .default)
        thumbnailTask = Task {
            await cache.setProject(project, projectDirectory: projectDirectory)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.thumbnailCache = cache
            }
            // Generate a small initial set of thumbnails for fast open
            await generateInitialThumbnails(count: 15)
            // Generate waveforms and remaining thumbnails at low priority
            Task(priority: .utility) {
                await generateInitialWaveforms()
                await generateInitialThumbnails(count: 50)
            }
        }
    }

    private func generateInitialThumbnails(count: Int = 50) async {
        guard let cache = thumbnailCache else { return }

        let duration = project.timeline.duration
        let thumbnailCount = min(count, Int(duration) + 1)
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        var newThumbnails: [TimeInterval: NSImage] = [:]

        for i in 0..<thumbnailCount {
            guard !Task.isCancelled else { return }
            let time = Double(i) * interval

            // Check if already loaded
            if thumbnails[time] != nil {
                newThumbnails[time] = thumbnails[time]
                continue
            }

            do {
                let cachedThumbnail = try await cache.getThumbnail(at: time)
                if let image = NSImage(data: cachedThumbnail.imageData) {
                    newThumbnails[time] = image
                }
            } catch {
                // Silently fail for thumbnail generation errors
                // Thumbnails are optional UI enhancement
            }
        }

        await MainActor.run {
            self.thumbnails = newThumbnails
        }
    }

    private func getThumbnailForTime(_ time: TimeInterval) -> NSImage? {
        // Find the closest thumbnail
        let sortedTimes = thumbnails.keys.sorted()
        guard let closestTime = sortedTimes.min(by: { abs($0 - time) < abs($1 - time) }) else {
            return nil
        }

        // Only return if within 2 seconds
        if abs(closestTime - time) <= 2.0 {
            return thumbnails[closestTime]
        }

        return nil
    }

    // MARK: - Waveform Management

    private func generateInitialWaveforms() async {
        guard let cache = thumbnailCache else { return }

        var newWaveforms: [String: [Float]] = [:]

        // Generate waveform for system audio if present
        if let audio = project.primarySources?.audio, let systemAudio = audio.system {
            do {
                let cachedWaveform = try await cache.getWaveform(for: systemAudio.path)
                newWaveforms[systemAudio.path] = cachedWaveform.samples
            } catch {
                // Silently fail for waveform generation errors
                // Waveforms are optional UI enhancement
            }
        }

        // Generate waveform for mic audio if present
        if let audio = project.primarySources?.audio, let micAudio = audio.mic {
            do {
                let cachedWaveform = try await cache.getWaveform(for: micAudio.path)
                newWaveforms[micAudio.path] = cachedWaveform.samples
            } catch {
                // Silently fail for waveform generation errors
                // Waveforms are optional UI enhancement
            }
        }

        await MainActor.run {
            self.waveforms = newWaveforms
        }
    }

    private func getWaveformForTrack(_ trackKind: TimelineTrackKind) -> [Float]? {
        let trackPath: String?

        switch trackKind {
        case .systemAudio:
            trackPath = project.primarySources?.audio?.system?.path
        case .micAudio:
            trackPath = project.primarySources?.audio?.mic?.path
        default:
            trackPath = nil
        }

        guard let path = trackPath else {
            return nil
        }

        return waveforms[path]
    }

    private var currentLayout: TimelineLayout {
        let basePPS: TimelineScalar = project.timeline.duration > 0
            ? max(pixelsPerSecond, (availableWidth - labelWidth) / TimelineScalar(project.timeline.duration))
            : pixelsPerSecond
        return TimelineLayout(
            duration: project.timeline.duration,
            pixelsPerSecond: basePPS * zoomScale,
            labelWidth: labelWidth
        )
    }

    var body: some View {
        let layout = currentLayout
        let tracks = TimelineTrackBuilder.tracks(for: project)
        let totalHeight = max(
            0,
            (TimelineScalar(tracks.count) * trackHeight) + (TimelineScalar(max(tracks.count - 1, 0)) * trackSpacing)
        )

        VStack(alignment: .leading, spacing: 12) {
            timelineToolbar
            segmentInspector
            timelineScrollContent(layout: layout, tracks: tracks, totalHeight: totalHeight)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let w = geo.size.width
                        Task { @MainActor in availableWidth = w }
                    }
                    .onChange(of: geo.size.width) { _, w in availableWidth = w }
            }
        )
        .onChange(of: projectDirectory) { _, newValue in
            if let path = newValue?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
        }
        .onAppear {
            if let path = projectDirectory?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
            // Auto-generate zoom suggestions if telemetry is available
            if hasCursorTelemetry && zoomSuggestions.isEmpty && !isGeneratingSuggestions {
                generateZoomSuggestions()
            }
        }
        .onDeleteCommand {
            deleteSelectedSegment()
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [.audio, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var timelineToolbar: some View {
        HStack(spacing: 12) {
            Text("Timeline")
                .font(.headline)

            Spacer()

            Button("Undo") { undoEdit() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!editor.canUndo)

            Button("Redo") { redoEdit() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!editor.canRedo)

            Button("Split") { splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!canSplitAtPlayhead)

            Button("Delete") { deleteSelectedSegment() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedSegmentId == nil)

            zoomSuggestionButtons
            importAndViewToggles
            zoomScaleControls
        }
    }

    @ViewBuilder
    private var zoomSuggestionButtons: some View {
        if !zoomSuggestions.isEmpty {
            Button {
                applyZoomSuggestions()
            } label: {
                Label("Apply (\(activeSuggestions.count)/\(zoomSuggestions.count))", systemImage: "checkmark.circle")
            }
            .disabled(activeSuggestions.isEmpty)
            .help("Apply selected zoom suggestions as keyframes")

            Button {
                zoomSuggestions = []
                dismissedSuggestionIds = []
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Dismiss all zoom suggestions")
        } else {
            Button {
                generateZoomSuggestions()
            } label: {
                Label("Suggest Zooms", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(isGeneratingSuggestions || !hasCursorTelemetry)
            .help(hasCursorTelemetry ? "Detect zoom points from cursor telemetry" : "No cursor telemetry available")
        }
    }

    @ViewBuilder
    private var importAndViewToggles: some View {
        Button {
            showImportPanel = true
        } label: {
            Label("Import", systemImage: "plus.circle")
        }
        .help("Import audio or image asset")

        Toggle("Thumbnails", isOn: $showThumbnails)
            .toggleStyle(.switch)
            .help("Show/hide video thumbnails in timeline")
            .disabled(thumbnailCache == nil)

        Toggle("Waveforms", isOn: $showWaveforms)
            .toggleStyle(.switch)
            .help("Show/hide audio waveforms in timeline")
            .disabled(thumbnailCache == nil || waveforms.isEmpty)
    }

    @ViewBuilder
    private var zoomScaleControls: some View {
        Button {
            zoomScale = max(minZoomScale, zoomScale - zoomStep)
        } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(zoomScale <= minZoomScale + 0.001)

        Text("\(Int(zoomScale * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
            zoomScale = min(maxZoomScale, zoomScale + zoomStep)
        } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(zoomScale >= maxZoomScale - 0.001)
    }

    // MARK: - Segment Inspector

    @ViewBuilder
    private var segmentInspector: some View {
        if let segId = selectedSegmentId,
           let segment = project.timeline.segments.first(where: { $0.id == segId }) {
            SegmentInspectorBar(
                segment: segment,
                projectCamera: project.canvas.layout.camera,
                onSpeedChange: { speed in
                    Task { await editor.updateSegmentSpeed(segmentId: segId, speed: speed) }
                },
                onCameraOverride: {
                    let camera = segment.cameraPosition ?? project.canvas.layout.camera
                    Task { await editor.updateSegmentCameraPosition(segmentId: segId, camera: camera) }
                },
                onCameraReset: {
                    Task { await editor.updateSegmentCameraPosition(segmentId: segId, camera: nil) }
                },
                onVolumeChange: { vol in
                    Task { await editor.updateSegmentVolume(segmentId: segId, volume: vol) }
                },
                onMuteToggle: { muted in
                    Task { await editor.updateSegmentAudioMuted(segmentId: segId, muted: muted) }
                }
            )
        }
    }

    // MARK: - Scroll Content

    private func timelineScrollContent(
        layout: TimelineLayout,
        tracks: [TimelineTrack],
        totalHeight: TimelineScalar
    ) -> some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                timelineTracks(layout: layout, tracks: tracks)

                if let selection {
                    TimelineRangeSelectionView(selection: selection, layout: layout, height: totalHeight)
                }

                ForEach(zoomSuggestions) { suggestion in
                    ZoomSuggestionMarker(
                        suggestion: suggestion,
                        xPosition: layout.xPosition(for: suggestion.timelineTime),
                        height: totalHeight,
                        isDismissed: dismissedSuggestionIds.contains(suggestion.id),
                        onToggle: {
                            if dismissedSuggestionIds.contains(suggestion.id) {
                                dismissedSuggestionIds.remove(suggestion.id)
                            } else {
                                dismissedSuggestionIds.insert(suggestion.id)
                            }
                        }
                    )
                }

                TimelinePlayheadView(
                    xPosition: layout.xPosition(for: playheadTime),
                    height: totalHeight
                )
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .gesture(timelineDragGesture(layout: layout))
            .onDrop(of: [.text], isTargeted: nil) { providers, location in
                handleDrop(providers: providers, location: location, layout: layout)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func timelineTracks(layout: TimelineLayout, tracks: [TimelineTrack]) -> some View {
        let allTracks = tracks
        return VStack(alignment: .leading, spacing: trackSpacing) {
            ForEach(allTracks) { track in
                timelineTrackContent(for: track, layout: layout)
                    .frame(width: layout.contentWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func timelineTrackContent(for track: TimelineTrack, layout: TimelineLayout) -> some View {
        let trackWaveform = getWaveformForTrack(track.kind)

        if track.kind == .overlay {
            TimelineOverlayTrackRow(
                overlays: track.overlays,
                layout: layout,
                height: trackHeight,
                selectedOverlayId: selectedOverlayId,
                onSelectOverlay: { id in
                    selectedOverlayId = id
                },
                onOverlayDragged: { overlayId, deltaX in
                    let item = editor.project.overlays.first { $0.id == overlayId }
                    guard let item else { return }
                    let newStart = max(0, item.start + deltaX)
                    let duration = item.end - item.start
                    Task {
                        await editor.updateOverlay(
                            projectId: editor.project.projectId,
                            overlayId: overlayId,
                            start: newStart,
                            end: newStart + duration
                        )
                    }
                }
            )
        } else {
            TimelineTrackRow(
                track: track,
                layout: layout,
                height: trackHeight,
                selectedSegmentId: selectedSegmentId,
                isInteractive: track.kind == .screen,
                isMuted: mutedTracks.contains(track.kind),
                showThumbnails: showThumbnails && track.kind == .screen,
                thumbnails: thumbnails,
                showWaveforms: showWaveforms && track.kind.isAudioTrack,
                waveformSamples: trackWaveform,
                volumeBinding: volumeBinding(for: track.kind),
                onSelectSegment: { segment in
                    selectedSegmentId = segment.id
                    playerViewModel.seek(to: segment.timelineIn)
                },
                onTrimDragChanged: { _, _, _ in
                    isTrimming = true
                },
                onTrimDragEnded: { segment, edge, deltaX in
                    isTrimming = false
                    applyTrim(for: segment, edge: edge, deltaX: deltaX, layout: layout)
                },
                onMediaItemDragged: { itemId, deltaX in
                    let deltaTime = TimeInterval(deltaX / layout.pixelsPerSecond)
                    Task {
                        guard let item = editor.project.mediaItems.first(where: { $0.id == itemId }) else { return }
                        let newTimelineIn = max(0, item.timelineIn + deltaTime)
                        await editor.updateMediaItem(id: itemId, timelineIn: newTimelineIn)
                    }
                },
                onSelectMediaItem: { itemId in
                    selectedMediaItemId = itemId
                },
                onToggleMute: {
                    if mutedTracks.contains(track.kind) {
                        mutedTracks.remove(track.kind)
                    } else {
                        mutedTracks.insert(track.kind)
                    }
                }
            )
        }
    }

    private func timelineDragGesture(layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isTrimming else { return }
                let time = layout.time(forXPosition: value.location.x)

                if dragStartTime == nil {
                    dragStartTime = time
                    playerViewModel.setScrubbing(true)
                }

                playerViewModel.seek(to: time)

                let startTime = dragStartTime ?? time
                if abs(value.translation.width) > 2 {
                    let rangeStart = min(startTime, time)
                    let rangeEnd = max(startTime, time)
                    selection = RangeSelection(startTime: rangeStart, endTime: rangeEnd)
                } else {
                    selection = nil
                }
            }
            .onEnded { value in
                guard !isTrimming else { return }
                let time = layout.time(forXPosition: value.location.x)
                playerViewModel.seek(to: time)

                if let startTime = dragStartTime, abs(value.translation.width) > 2 {
                    let rangeStart = min(startTime, time)
                    let rangeEnd = max(startTime, time)
                    selection = RangeSelection(startTime: rangeStart, endTime: rangeEnd)
                } else {
                    selection = nil
                }

                dragStartTime = nil
                playerViewModel.setScrubbing(false)
            }
    }

    private func volumeBinding(for kind: TimelineTrackKind) -> Binding<Float>? {
        switch kind {
        case .systemAudio: return $playerViewModel.systemAudioVolume
        case .micAudio: return $playerViewModel.micAudioVolume
        default: return nil
        }
    }

    private var canSplitAtPlayhead: Bool {
        TimelineEditingHelper.segmentForSplit(at: playheadTime, in: project.timeline.segments) != nil
    }

    private func splitAtPlayhead() {
        guard let segment = TimelineEditingHelper.segmentForSplit(at: playheadTime, in: project.timeline.segments) else {
            return
        }

        Task {
            let result = await editor.split(segmentId: segment.id, at: playheadTime)
            if case .successWithInfo(_, .splitCreated(let newSegmentId)) = result {
                selectedSegmentId = newSegmentId
            }
        }
    }

    private func deleteSelectedSegment() {
        guard let selectedSegmentId else { return }

        Task {
            _ = await editor.delete(segmentId: selectedSegmentId)
        }

        self.selectedSegmentId = nil
    }

    private func undoEdit() {
        Task {
            let didUndo = await editor.undo()
            if didUndo {
                selectedSegmentId = nil
                selection = nil
                let clampedTime = min(playheadTime, editor.project.timeline.duration)
                playerViewModel.seek(to: clampedTime)
            }
        }
    }

    private func redoEdit() {
        Task {
            let didRedo = await editor.redo()
            if didRedo {
                selectedSegmentId = nil
                selection = nil
                let clampedTime = min(playheadTime, editor.project.timeline.duration)
                playerViewModel.seek(to: clampedTime)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, layout: TimelineLayout) -> Bool {
        guard let provider = providers.first else { return false }
        
        // We expect a UUID string for the take ID
        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { idString, error in
                guard let uuidString = idString as? String,
                      let takeId = UUID(uuidString: uuidString) else { return }
                
                Task { @MainActor in
                    guard let take = self.editor.project.takes.first(where: { $0.id == takeId }) else { return }
                    
                    // Calculate drop time
                    let dropTime = layout.time(forXPosition: location.x)
                    
                    // Default fallback duration
                    var duration: TimeInterval = 10.0
                    
                    // Try to get actual duration from file
                    if let projectDir = self.projectDirectory {
                        let videoPath = projectDir.appendingPathComponent(take.sources.screen.path)
                        let asset = AVURLAsset(url: videoPath)
                        if let assetDuration = try? await asset.load(.duration) {
                            duration = assetDuration.seconds
                        }
                    }
                    
                    // Add segment
                    _ = await self.editor.addSegment(
                        takeId: takeId,
                        sourceIn: 0,
                        sourceOut: duration,
                        timelineIn: dropTime
                    )
                }
            }
            return true
        }
        
        return false
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first,
              let projectDir = projectDirectory else { return }

        let ext = url.pathExtension.lowercased()
        let isAudio = ["mp3", "wav", "m4a", "aac", "aiff", "flac"].contains(ext)
        let isImage = ["png", "jpg", "jpeg", "heic", "webp", "tiff"].contains(ext)
        guard isAudio || isImage else { return }

        let type: Project.MediaItemType = isAudio ? .audio : .image
        let fileName = url.lastPathComponent
        let currentPlayhead = playheadTime

        Task {
            let fileManager = FileManager.default
            let assetsDir = projectDir.appendingPathComponent("assets", isDirectory: true)
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

            let destURL = assetsDir.appendingPathComponent(fileName)

            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                return
            }

            var duration: TimeInterval = 5.0
            if isAudio {
                let asset = AVURLAsset(url: destURL)
                if let assetDuration = try? await asset.load(.duration) {
                    duration = assetDuration.seconds
                }
            }

            let item = Project.MediaItem(
                type: type,
                path: "assets/\(fileName)",
                name: fileName,
                timelineIn: currentPlayhead,
                duration: duration
            )

            await editor.addMediaItem(item)
        }
    }

    private func applyTrim(
        for segment: Project.Timeline.Segment,
        edge: TimelineTrimEdge,
        deltaX: TimelineScalar,
        layout: TimelineLayout
    ) {
        let deltaTime = TimeInterval(deltaX / layout.pixelsPerSecond)

        switch edge {
        case .leading:
            let proposedTimelineIn = segment.timelineIn + deltaTime
            let clampedTimelineIn = TimelineEditingHelper.clampedTimelineIn(
                for: segment,
                proposedTime: proposedTimelineIn,
                minimumDuration: minimumTrimDuration
            )
            guard clampedTimelineIn != segment.timelineIn else { return }

            let newSourceIn = TimelineEditingHelper.sourceIn(for: segment, newTimelineIn: clampedTimelineIn)
            Task {
                _ = await editor.trimIn(segmentId: segment.id, newSourceIn: newSourceIn)
            }
        case .trailing:
            let proposedTimelineOut = segment.timelineOut + deltaTime
            let clampedTimelineOut = TimelineEditingHelper.clampedTimelineOut(
                for: segment,
                proposedTime: proposedTimelineOut,
                minimumDuration: minimumTrimDuration
            )
            guard clampedTimelineOut != segment.timelineOut else { return }

            let newSourceOut = TimelineEditingHelper.sourceOut(for: segment, newTimelineOut: clampedTimelineOut)
            Task {
                _ = await editor.trimOut(segmentId: segment.id, newSourceOut: newSourceOut)
            }
        }
    }

    // MARK: - Zoom Suggestions (moved to TimelineView+ZoomSuggestions.swift)

    private var zoomSuggestionGenerator: ZoomSuggestionGenerator {
        ZoomSuggestionGenerator(project: project, projectDirectory: projectDirectory)
    }

    private var hasCursorTelemetry: Bool {
        project.primarySources?.telemetry?.cursor != nil
    }

    private var activeSuggestions: [ZoomSuggestion] {
        zoomSuggestions.filter { !dismissedSuggestionIds.contains($0.id) }
    }

    private func generateZoomSuggestions() {
        guard hasCursorTelemetry, let projDir = projectDirectory else {
            LogDebug(.telemetry, "No cursor telemetry or project directory")
            return
        }

        isGeneratingSuggestions = true

        Task {
            let generator = ZoomSuggestionGenerator(project: project, projectDirectory: projDir)
            let suggestions = await generator.generate()

            if !suggestions.isEmpty {
                if let plan = try? await generator.applyAsPlan(suggestions) {
                    await playerViewModel.previewEngine?.setZoomPlan(plan)
                    LogInfo(.telemetry, "Auto-applied zoom plan with \(plan.keyframes.count) keyframes")
                }
            }

            await MainActor.run {
                zoomSuggestions = suggestions
                isGeneratingSuggestions = false
            }
        }
    }

    private func applyZoomSuggestions() {
        let suggestions = activeSuggestions
        guard !suggestions.isEmpty else { return }

        Task {
            let generator = ZoomSuggestionGenerator(project: project, projectDirectory: projectDirectory)
            if let plan = try? await generator.applyAsPlan(suggestions) {
                await playerViewModel.previewEngine?.setZoomPlan(plan)
            }

            await enableZoomOnAllSegments()

            await MainActor.run {
                zoomSuggestions = []
                dismissedSuggestionIds = []
            }
        }
    }

    private func enableZoomOnAllSegments() async {
        let zoomConfig = Project.Timeline.ZoomConfiguration(
            enabled: true,
            intensity: .normal
        )
        var updatedProject = editor.project
        for i in updatedProject.timeline.segments.indices {
            updatedProject.timeline.segments[i].zoom = zoomConfig
        }
        await editor.setProject(updatedProject)
    }
}

