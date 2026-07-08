//
//  TimelineView.swift
//  App
//
//  Created by Ralphy on 2026-01-21.
//
//  Main timeline composition. Helper logic lives in:
//    - TimelineView+Thumbnails.swift   (thumbnail/waveform generation)
//    - TimelineView+DragDrop.swift     (playhead drag, drop, import, trim)
//    - TimelineView+EditActions.swift  (split/delete/undo/redo/volume)
//    - TimelineView+ZoomSuggestions.swift (zoom suggestion workflow)
//    - TimelineView+Subviews.swift     (track rows, segment views)
//

import SwiftUI
import EngineKit
import CoreGraphics
import UniformTypeIdentifiers

struct TimelineView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    let projectDirectory: URL?
    @Binding var mutedTracks: Set<TimelineTrackKind>
    @Binding var selectedSegmentId: String?
    @Binding var selectedMediaItemId: UUID?
    @Binding var selectedOverlayId: UUID?

    // Layout constants — non-private so the track-rendering methods (in
    // TimelineView+Tracks.swift) can read them.
    let trackHeight: TimelineScalar = 34
    let trackSpacing: TimelineScalar = 8
    private let pixelsPerSecond: TimelineScalar = 40
    let labelWidth: TimelineScalar = 160
    /// Hard ceiling for zoom-in density: 1 second = 240pt is plenty for frame-level cuts.
    private let maxPixelsPerSecond: TimelineScalar = 240
    let minimumTrimDuration: TimeInterval = 0.1

    @State var zoomScale: TimelineScalar = 1
    @State var availableWidth: CGFloat = 800
    @State var selection: RangeSelection?
    @State var dragStartTime: TimeInterval?
    @State var isTrimming = false
    @State var showImportPanel = false
    @State var selectedVideoClip: SelectedVideoClip?
    @State var showVideoClipEffects = false
    @State var importNotice: String?
    @State var zoomSuggestions: [ZoomSuggestion] = []
    @State var dismissedSuggestionIds: Set<UUID> = []
    @State var isGeneratingSuggestions = false
    @State var selectedManualKeyframeId: UUID?
    @State var thumbnailTask: Task<Void, Never>?

    @State var thumbnailCache: ThumbnailCache?
    @State var thumbnails: [TimeInterval: NSImage] = [:]
    @State var showThumbnails: Bool = true

    @State var waveforms: [String: [Float]] = [:]
    @State var showWaveforms: Bool = true

    var project: Project { editor.project }

    var playheadTime: Double { playerViewModel.currentTime }

    var manualZoomKeyframes: [ZoomPlanGenerator.ZoomKeyframe] {
        project.manualZoomKeyframes ?? []
    }

    /// Pixels/second that makes the whole timeline fit the visible width.
    private var fitPPS: TimelineScalar {
        guard project.timeline.duration > 0 else { return pixelsPerSecond }
        return max(1, (availableWidth - labelWidth - 8) / TimelineScalar(project.timeline.duration))
    }

    private var currentLayout: TimelineLayout {
        // 100% = the whole timeline (recorded + imported) fits the visible
        // width; zoom multiplies from there, capped for frame-level editing.
        let pps = min(fitPPS * zoomScale, max(fitPPS, maxPixelsPerSecond))
        return TimelineLayout(
            duration: project.timeline.duration,
            pixelsPerSecond: pps,
            labelWidth: labelWidth
        )
    }

    private var canZoomIn: Bool {
        currentLayout.pixelsPerSecond < max(fitPPS, maxPixelsPerSecond) - 0.5
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
            videoClipInspector
            timelineScrollContent(layout: layout, tracks: tracks, totalHeight: totalHeight)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let w = geo.size.width
                        Task { @MainActor in availableWidth = w }
                    }
                    .onChangeCompat(of: geo.size.width) { w in availableWidth = w }
            }
        )
        .onChangeCompat(of: projectDirectory) { newValue in
            if let path = newValue?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
        }
        .onAppear {
            if let path = projectDirectory?.path {
                initializeThumbnailCache(projectDirectory: path)
            }
            if FeatureFlags.autoZoom && hasCursorTelemetry && zoomSuggestions.isEmpty && !isGeneratingSuggestions {
                generateZoomSuggestions()
            }
        }
        .onDeleteCommand {
            deleteSelectedSegment()
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [.audio, .image, .movie],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        .alert(
            "Lower-resolution video",
            isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
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
        .help("Import video, audio or image asset")

        Menu {
            Toggle("Thumbnails", isOn: $showThumbnails)
                .disabled(thumbnailCache == nil)
            Toggle("Waveforms", isOn: $showWaveforms)
                .disabled(thumbnailCache == nil || waveforms.isEmpty)
            Divider()
            Toggle("Zoom Plan", isOn: $playerViewModel.showZoom)
            Divider()
            Toggle("Cursor", isOn: $playerViewModel.showCursor)
            Toggle("Clicks", isOn: $playerViewModel.showClicks)
            Toggle("Keystrokes", isOn: $playerViewModel.showKeystrokes)
        } label: {
            Label("View", systemImage: "eye")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Timeline and preview visibility options")
    }

    @ViewBuilder
    private var zoomScaleControls: some View {
        Button {
            zoomScale = max(1, zoomScale / 2)
        } label: {
            Image(systemName: "minus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(zoomScale <= 1.001)
        .help("Zoom out (100% = whole timeline)")

        Button("Fit") {
            zoomScale = 1
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .disabled(zoomScale <= 1.001)
        .help("Fit the whole timeline in view")

        Text("\(Int(zoomScale * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
            zoomScale = zoomScale * 2
        } label: {
            Image(systemName: "plus.magnifyingglass")
        }
        .buttonStyle(.borderless)
        .disabled(!canZoomIn)
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
        ZStack(alignment: .topLeading) {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 2) {
            TimelineRulerView(layout: layout) { time in
                playerViewModel.seek(to: time)
            }
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

                // Manual zoom keyframe markers + zoom curve
                if !manualZoomKeyframes.isEmpty {
                    ZoomCurveOverlay(
                        keyframes: manualZoomKeyframes,
                        layout: layout,
                        height: totalHeight,
                        maxZoomLevel: 4.0
                    )
                }

                ForEach(manualZoomKeyframes) { kf in
                    ManualZoomKeyframeMarker(
                        keyframe: kf,
                        xPosition: layout.xPosition(for: kf.timestamp),
                        height: totalHeight,
                        pixelsPerSecond: layout.pixelsPerSecond,
                        isSelected: selectedManualKeyframeId == kf.id,
                        onTap: {
                            selectedManualKeyframeId = (selectedManualKeyframeId == kf.id) ? nil : kf.id
                        },
                        onDragChanged: { newTime in
                            let clamped = max(0, min(project.timeline.duration, newTime))
                            editor.updateManualZoomKeyframeTimestampLive(id: kf.id, timestamp: clamped)
                        },
                        onDragEnded: {
                            Task {
                                await editor.commitManualZoomKeyframeDrag()
                                await playerViewModel.applyEffectiveZoomPlan(freshProject: editor.project)
                            }
                        },
                        onLiveUpdate: {
                            Task { @MainActor in
                                playerViewModel.applyEffectiveZoomPlan(freshProject: editor.project)
                            }
                        },
                        onContextMenuDelete: {
                            Task {
                                await editor.removeManualZoomKeyframe(id: kf.id)
                                await playerViewModel.applyEffectiveZoomPlan(freshProject: editor.project)
                                if selectedManualKeyframeId == kf.id {
                                    selectedManualKeyframeId = nil
                                }
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
        }
        // Fixed label column: stays put while the timeline content scrolls
        // beneath it (clips slide under the opaque labels).
        fixedTrackLabels(tracks: tracks)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The pinned label column rendered above the horizontal scroll view.
    private func fixedTrackLabels(tracks: [TimelineTrack]) -> some View {
        VStack(alignment: .leading, spacing: trackSpacing) {
            ForEach(tracks) { track in
                if track.kind == .overlay {
                    let overlayRows = Self.computeOverlayRows(overlays: track.overlays)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(overlayRows.enumerated()), id: \.element.id) { index, _ in
                            Text(overlayRows.count > 1 ? "Overlay \(index + 1)" : "Overlays")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.leading, 6)
                                .frame(height: trackHeight, alignment: .leading)
                        }
                    }
                } else if track.kind == .subtitle {
                    let hidden = mutedTracks.contains(.subtitle)
                    Button {
                        if hidden { mutedTracks.remove(.subtitle) } else { mutedTracks.insert(.subtitle) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: hidden ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                            Text("Subtitles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(hidden ? "Show subtitles in the preview" : "Hide subtitles in the preview")
                    .padding(.leading, 6)
                    .frame(height: trackHeight)
                } else {
                    TimelineTrackLabelView(
                        track: track,
                        isMuted: track.engineTrackId != nil ? track.engineMuted : mutedTracks.contains(track.kind),
                        volumeBinding: volumeBinding(for: track.kind),
                        onToggleMute: {
                            if let trackId = track.engineTrackId {
                                let muted = track.engineMuted
                                Task { _ = await editor.setTrackMuted(trackId: trackId, muted: !muted) }
                            } else if mutedTracks.contains(track.kind) {
                                mutedTracks.remove(track.kind)
                            } else {
                                mutedTracks.insert(track.kind)
                            }
                        }
                    )
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: trackHeight)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if let trackId = track.engineTrackId {
                            Button("Move Row Up") {
                                Task { _ = await editor.moveVideoTrack(trackId: trackId, up: true) }
                            }
                            Button("Move Row Down") {
                                Task { _ = await editor.moveVideoTrack(trackId: trackId, up: false) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, TimelineRulerView.rulerHeight + 2)
        .padding(.vertical, 4)
        .frame(width: labelWidth + 6, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
    }

    private func timelineTracks(layout: TimelineLayout, tracks: [TimelineTrack]) -> some View {
        let allTracks = tracks
        return VStack(alignment: .leading, spacing: trackSpacing) {
            ForEach(allTracks) { track in
                if track.kind == .overlay {
                    let overlayRows = Self.computeOverlayRows(overlays: track.overlays)
                    VStack(spacing: 4) {
                        ForEach(Array(overlayRows.enumerated()), id: \.element.id) { index, row in
                            TimelineOverlayTrackRow(
                                editor: editor,
                                overlays: row.overlays,
                                layout: layout,
                                height: trackHeight,
                                selectedOverlayId: $selectedOverlayId,
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
                                },
                                onPopoverOpened: { startTime in
                                    playerViewModel.seek(to: startTime)
                                },
                                rowLabel: overlayRows.count > 1 ? "Overlay \(index + 1)" : "Overlays",
                                showsLabel: false
                            )
                            .frame(height: trackHeight)
                        }
                    }
                    .frame(width: layout.contentWidth, alignment: .leading)
                } else if track.kind == .subtitle {
                    TimelineSubtitleTrackRow(
                        cues: track.overlays,
                        layout: layout,
                        height: trackHeight,
                        selectedOverlayId: $selectedOverlayId,
                        onSeek: { time in playerViewModel.seek(to: time) },
                        onMove: { id, deltaTime in
                            guard let cue = editor.project.subtitles.first(where: { $0.id == id }) else { return }
                            let duration = cue.end - cue.start
                            let newStart = max(0, cue.start + deltaTime)
                            Task { await editor.updateSubtitle(id: id, start: newStart, end: newStart + duration) }
                        },
                        onTrim: { id, edge, deltaTime in
                            guard let cue = editor.project.subtitles.first(where: { $0.id == id }) else { return }
                            switch edge {
                            case .leading:
                                let newStart = min(max(0, cue.start + deltaTime), cue.end - 0.2)
                                Task { await editor.updateSubtitle(id: id, start: newStart) }
                            case .trailing:
                                let newEnd = max(cue.start + 0.2, cue.end + deltaTime)
                                Task { await editor.updateSubtitle(id: id, end: newEnd) }
                            }
                        }
                    )
                    // Clamp height like the overlay rows: the row contains a
                    // vertically-flexible Color.clear that would otherwise absorb
                    // slack space and push the right-side tracks out of alignment
                    // with the fixed label column.
                    .frame(width: layout.contentWidth, height: trackHeight, alignment: .leading)
                } else {
                    timelineTrackContent(for: track, layout: layout)
                        .frame(width: layout.contentWidth, alignment: .leading)
                }
            }
        }
    }
}
