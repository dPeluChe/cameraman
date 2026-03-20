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

struct TimelineView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval
    let projectDirectory: URL?

    private let trackHeight: TimelineScalar = 34
    private let trackSpacing: TimelineScalar = 8
    private let pixelsPerSecond: TimelineScalar = 40
    private let labelWidth: TimelineScalar = 120
    private let minZoomScale: TimelineScalar = 0.5
    private let maxZoomScale: TimelineScalar = 4
    private let zoomStep: TimelineScalar = 0.25
    private let minimumTrimDuration: TimeInterval = 0.1

    @State private var zoomScale: TimelineScalar = 1
    @State private var selection: RangeSelection?
    @State private var dragStartTime: TimeInterval?
    @State private var selectedSegmentId: String?
    @State private var isTrimming = false

    // Thumbnail cache
    @State private var thumbnailCache: ThumbnailCache?
    @State private var thumbnails: [TimeInterval: NSImage] = [:]
    @State private var showThumbnails: Bool = true

    // Waveform cache
    @State private var waveforms: [String: [Float]] = [:]
    @State private var showWaveforms: Bool = true

    private var project: Project { editor.project }

    // MARK: - Thumbnail Management

    private func initializeThumbnailCache(projectDirectory: String) {
        let cache = ThumbnailCache(configuration: .default)
        Task {
            await cache.setProject(project, projectDirectory: projectDirectory)
            await MainActor.run {
                self.thumbnailCache = cache
            }
            // Pre-generate thumbnails for better performance
            await generateInitialThumbnails()
            // Pre-generate waveforms for audio tracks
            await generateInitialWaveforms()
        }
    }

    private func generateInitialThumbnails() async {
        guard let cache = thumbnailCache else { return }

        // Generate thumbnails at regular intervals
        let duration = project.timeline.duration
        let thumbnailCount = min(50, Int(duration) + 1)
        let interval = duration / Double(max(thumbnailCount - 1, 1))

        var newThumbnails: [TimeInterval: NSImage] = [:]

        for i in 0..<thumbnailCount {
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

    var body: some View {
        let layout = TimelineLayout(
            duration: project.timeline.duration,
            pixelsPerSecond: pixelsPerSecond * zoomScale,
            labelWidth: labelWidth
        )
        let tracks = TimelineTrackBuilder.tracks(for: project)
        let totalHeight = max(
            0,
            (TimelineScalar(tracks.count) * trackHeight) + (TimelineScalar(max(tracks.count - 1, 0)) * trackSpacing)
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Timeline")
                    .font(.headline)

                Spacer()

                Button("Undo") {
                    undoEdit()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!editor.canUndo)

                Button("Redo") {
                    redoEdit()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!editor.canRedo)

                Button("Split") {
                    splitAtPlayhead()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!canSplitAtPlayhead)

                Button("Delete") {
                    deleteSelectedSegment()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedSegmentId == nil)

                Toggle("Thumbnails", isOn: $showThumbnails)
                    .toggleStyle(.switch)
                    .help("Show/hide video thumbnails in timeline")
                    .disabled(thumbnailCache == nil)

                Toggle("Waveforms", isOn: $showWaveforms)
                    .toggleStyle(.switch)
                    .help("Show/hide audio waveforms in timeline")
                    .disabled(thumbnailCache == nil || waveforms.isEmpty)

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

            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: trackSpacing) {
                        ForEach(tracks) { track in
                            let trackWaveform = getWaveformForTrack(track.kind)

                            TimelineTrackRow(
                                track: track,
                                layout: layout,
                                height: trackHeight,
                                selectedSegmentId: selectedSegmentId,
                                isInteractive: track.kind == .screen,
                                showThumbnails: showThumbnails && track.kind == .screen,
                                thumbnails: thumbnails,
                                showWaveforms: showWaveforms && (track.kind == .systemAudio || track.kind == .micAudio),
                                waveformSamples: trackWaveform,
                                onSelectSegment: { segment in
                                    selectedSegmentId = segment.id
                                    playheadTime = segment.timelineIn
                                },
                                onTrimDragChanged: { _, _, _ in
                                    isTrimming = true
                                },
                                onTrimDragEnded: { segment, edge, deltaX in
                                    isTrimming = false
                                    applyTrim(
                                        for: segment,
                                        edge: edge,
                                        deltaX: deltaX,
                                        layout: layout
                                    )
                                }
                            )
                                .frame(width: layout.contentWidth, alignment: .leading)
                        }
                    }

                    if let selection {
                        TimelineRangeSelectionView(selection: selection, layout: layout, height: totalHeight)
                    }

                    TimelinePlayheadView(
                        xPosition: layout.xPosition(for: playheadTime),
                        height: totalHeight
                    )
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isTrimming else { return }
                            let time = layout.time(forXPosition: value.location.x)
                            playheadTime = time
                            if dragStartTime == nil {
                                dragStartTime = time
                            }

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
                            playheadTime = time

                            if let startTime = dragStartTime, abs(value.translation.width) > 2 {
                                let rangeStart = min(startTime, time)
                                let rangeEnd = max(startTime, time)
                                selection = RangeSelection(startTime: rangeStart, endTime: rangeEnd)
                            } else {
                                selection = nil
                            }

                            dragStartTime = nil
                        }
                )
                .onDrop(of: [.text], isTargeted: nil) { providers, location in
                    handleDrop(providers: providers, location: location, layout: layout)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onChange(of: projectDirectory) { _, newValue in
            if let path = newValue?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
        }
        .onAppear {
            if let path = projectDirectory?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
        }
        .onDeleteCommand {
            deleteSelectedSegment()
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
                playheadTime = min(playheadTime, editor.project.timeline.duration)
            }
        }
    }

    private func redoEdit() {
        Task {
            let didRedo = await editor.redo()
            if didRedo {
                selectedSegmentId = nil
                selection = nil
                playheadTime = min(playheadTime, editor.project.timeline.duration)
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
}

