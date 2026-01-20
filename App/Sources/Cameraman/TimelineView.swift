//
//  TimelineView.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//

import SwiftUI
import EngineKit
import CoreGraphics

typealias TimelineScalar = CoreGraphics.CGFloat

enum TimelineTrackKind: String, CaseIterable, Identifiable {
    case screen
    case camera
    case systemAudio
    case micAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen:
            return "Screen"
        case .camera:
            return "Camera"
        case .systemAudio:
            return "System Audio"
        case .micAudio:
            return "Mic Audio"
        }
    }

    var color: Color {
        switch self {
        case .screen:
            return Color.blue.opacity(0.85)
        case .camera:
            return Color.green.opacity(0.85)
        case .systemAudio:
            return Color.orange.opacity(0.85)
        case .micAudio:
            return Color.pink.opacity(0.85)
        }
    }
}

struct TimelineTrack: Identifiable {
    let kind: TimelineTrackKind
    let segments: [Project.Timeline.Segment]

    var id: TimelineTrackKind { kind }
    var label: String { kind.label }
    var color: Color { kind.color }
}

enum TimelineTrackBuilder {
    static func tracks(for project: Project) -> [TimelineTrack] {
        var tracks: [TimelineTrack] = [
            TimelineTrack(kind: .screen, segments: project.timeline.segments)
        ]

        if project.sources.camera != nil {
            tracks.append(TimelineTrack(kind: .camera, segments: project.timeline.segments))
        }

        if project.sources.audio?.system != nil {
            tracks.append(TimelineTrack(kind: .systemAudio, segments: project.timeline.segments))
        }

        if project.sources.audio?.mic != nil {
            tracks.append(TimelineTrack(kind: .micAudio, segments: project.timeline.segments))
        }

        return tracks
    }
}

struct TimelineLayout {
    let duration: TimeInterval
    let pixelsPerSecond: TimelineScalar
    let labelWidth: TimelineScalar
    let minimumSegmentWidth: TimelineScalar = 6

    var contentWidth: TimelineScalar {
        let timelineWidth = max(1, TimelineScalar(duration) * pixelsPerSecond)
        return labelWidth + timelineWidth
    }

    func xPosition(for time: TimeInterval) -> TimelineScalar {
        let safeTime = max(0, time)
        return labelWidth + TimelineScalar(safeTime) * pixelsPerSecond
    }

    func segmentWidth(for duration: TimeInterval) -> TimelineScalar {
        let safeDuration = max(0, duration)
        return max(minimumSegmentWidth, TimelineScalar(safeDuration) * pixelsPerSecond)
    }

    func time(forXPosition xPosition: TimelineScalar) -> TimeInterval {
        let effectivePixelsPerSecond = max(pixelsPerSecond, 0.001)
        let timelineX = max(0, xPosition - labelWidth)
        let time = TimeInterval(timelineX / effectivePixelsPerSecond)
        return min(max(0, time), duration)
    }
}

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
        if let audio = project.sources.audio, let systemAudio = audio.system {
            do {
                let cachedWaveform = try await cache.getWaveform(for: systemAudio.path)
                newWaveforms[systemAudio.path] = cachedWaveform.samples
            } catch {
                // Silently fail for waveform generation errors
                // Waveforms are optional UI enhancement
            }
        }

        // Generate waveform for mic audio if present
        if let audio = project.sources.audio, let micAudio = audio.mic {
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
            trackPath = project.sources.audio?.system?.path
        case .micAudio:
            trackPath = project.sources.audio?.mic?.path
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
            }
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onChange(of: projectDirectory) { newValue in
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

private struct TimelineTrackRow: View {
    let track: TimelineTrack
    let layout: TimelineLayout
    let height: TimelineScalar
    let selectedSegmentId: String?
    let isInteractive: Bool
    let showThumbnails: Bool
    let thumbnails: [TimeInterval: NSImage]
    let showWaveforms: Bool
    let waveformSamples: [Float]?
    let onSelectSegment: (Project.Timeline.Segment) -> Void
    let onTrimDragChanged: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void
    let onTrimDragEnded: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            Text(track.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: layout.labelWidth - 12, alignment: .leading)
                .padding(.leading, 8)

            ForEach(track.segments) { segment in
                let isSelected = segment.id == selectedSegmentId
                let width = layout.segmentWidth(for: segment.timelineDuration)
                let xPosition = layout.xPosition(for: segment.timelineIn)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(track.color.opacity(showThumbnails || showWaveforms ? 0.3 : 1.0))
                    .frame(width: width, height: height - 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay {
                        // Render thumbnails for screen track
                        if showThumbnails && !thumbnails.isEmpty && track.kind == .screen {
                            TimelineThumbnailStrip(
                                segment: segment,
                                layout: layout,
                                thumbnails: thumbnails,
                                height: height - 10
                            )
                        }

                        // Render waveforms for audio tracks
                        if showWaveforms, let samples = waveformSamples, (track.kind == .systemAudio || track.kind == .micAudio) {
                            TimelineWaveformStrip(
                                segment: segment,
                                layout: layout,
                                waveformSamples: samples,
                                height: height - 10,
                                color: track.color
                            )
                        }
                    }
                    .overlay(alignment: .leading) {
                        if isInteractive && isSelected {
                            TimelineTrimHandle(
                                edge: .leading,
                                height: height,
                                onDragChanged: { deltaX in
                                    onTrimDragChanged(segment, .leading, deltaX)
                                },
                                onDragEnded: { deltaX in
                                    onTrimDragEnded(segment, .leading, deltaX)
                                }
                            )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isInteractive && isSelected {
                            TimelineTrimHandle(
                                edge: .trailing,
                                height: height,
                                onDragChanged: { deltaX in
                                    onTrimDragChanged(segment, .trailing, deltaX)
                                },
                                onDragEnded: { deltaX in
                                    onTrimDragEnded(segment, .trailing, deltaX)
                                }
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isInteractive else { return }
                        onSelectSegment(segment)
                    }
                    .offset(x: xPosition)
            }
        }
        .frame(height: height)
    }
}

private struct TimelinePlayheadView: View {
    let xPosition: TimelineScalar
    let height: TimelineScalar

    var body: some View {
        Rectangle()
            .fill(Color.red.opacity(0.9))
            .frame(width: 2, height: height)
            .offset(x: xPosition)
    }
}

private struct TimelineRangeSelectionView: View {
    let selection: RangeSelection
    let layout: TimelineLayout
    let height: TimelineScalar

    var body: some View {
        let startX = layout.xPosition(for: selection.startTime)
        let endX = layout.xPosition(for: selection.endTime)
        let width = max(2, endX - startX)

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .offset(x: startX)
    }
}

private enum TimelineTrimEdge {
    case leading
    case trailing
}

private struct TimelineTrimHandle: View {
    let edge: TimelineTrimEdge
    let height: TimelineScalar
    let onDragChanged: (TimelineScalar) -> Void
    let onDragEnded: (TimelineScalar) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 6, height: height - 14)
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 0)
            .padding(edge == .leading ? .leading : .trailing, 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDragChanged(value.translation.width)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation.width)
                    }
            )
    }
}

/// Renders a strip of thumbnails within a timeline segment
private struct TimelineThumbnailStrip: View {
    let segment: Project.Timeline.Segment
    let layout: TimelineLayout
    let thumbnails: [TimeInterval: NSImage]
    let height: TimelineScalar

    private let thumbnailSpacing: TimelineScalar = 4
    private let minThumbnailWidth: TimelineScalar = 30

    var body: some View {
        let segmentWidth = layout.segmentWidth(for: segment.timelineDuration)

        // Calculate how many thumbnails fit in the segment
        let thumbnailCount = max(1, Int(segmentWidth / (minThumbnailWidth + thumbnailSpacing)))
        let interval = segment.timelineDuration / Double(max(thumbnailCount - 1, 1))

        ZStack {
            ForEach(0..<thumbnailCount, id: \.self) { index in
                let time = segment.timelineIn + (Double(index) * interval)
                let relativeTime = time - segment.timelineIn
                let thumbnailX = (relativeTime / segment.timelineDuration) * segmentWidth

                if let thumbnail = findClosestThumbnail(for: time) {
                    GeometryReader { geometry in
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: minThumbnailWidth, height: height)
                            .clipped()
                            .opacity(0.7)
                            .offset(x: thumbnailX)
                    }
                }
            }
        }
        .frame(width: segmentWidth, height: height)
        .clipped()
    }

    private func findClosestThumbnail(for time: TimeInterval) -> NSImage? {
        let sortedTimes = thumbnails.keys.sorted()
        guard let closestTime = sortedTimes.min(by: { abs($0 - time) < abs($1 - time) }) else {
            return nil
        }

        // Only return if within 1 second
        if abs(closestTime - time) <= 1.0 {
            return thumbnails[closestTime]
        }

        return nil
    }
}

/// Renders an audio waveform visualization within a timeline segment
private struct TimelineWaveformStrip: View {
    let segment: Project.Timeline.Segment
    let layout: TimelineLayout
    let waveformSamples: [Float]
    let height: TimelineScalar
    let color: Color

    private let waveformPadding: TimelineScalar = 2

    var body: some View {
        let segmentWidth = layout.segmentWidth(for: segment.timelineDuration)
        let effectiveHeight = max(2, height - (waveformPadding * 2))

        // Map waveform samples to segment time range
        let segmentSamples = samplesForSegment()

        GeometryReader { geometry in
            Path { path in
                guard !segmentSamples.isEmpty else { return }

                let sampleWidth = segmentWidth / CGFloat(segmentSamples.count)
                let centerY = effectiveHeight / 2

                for (index, sample) in segmentSamples.enumerated() {
                    let x = CGFloat(index) * sampleWidth

                    // Scale sample to height (samples are normalized -1.0 to 1.0)
                    let amplitude = CGFloat(abs(sample)) * centerY
                    let yStart = centerY - amplitude
                    let yEnd = centerY + amplitude

                    path.move(to: CGPoint(x: x, y: yStart))
                    path.addLine(to: CGPoint(x: x, y: yEnd))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
        }
        .frame(width: segmentWidth, height: height)
        .padding(.vertical, waveformPadding)
    }

    /// Extract waveform samples for this segment's time range
    private func samplesForSegment() -> [Float] {
        guard !waveformSamples.isEmpty else { return [] }

        let totalDuration = layout.duration
        let sampleCount = waveformSamples.count

        // Calculate sample range for this segment
        let startRatio = segment.timelineIn / totalDuration
        let endRatio = segment.timelineOut / totalDuration

        let startIndex = max(0, Int(startRatio * Double(sampleCount)))
        let endIndex = min(sampleCount, Int(endRatio * Double(sampleCount)))

        guard endIndex > startIndex else { return [] }

        return Array(waveformSamples[startIndex..<endIndex])
    }
}

