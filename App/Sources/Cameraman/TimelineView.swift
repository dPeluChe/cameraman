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

    private let trackHeight: TimelineScalar = 34
    private let trackSpacing: TimelineScalar = 8
    private let pixelsPerSecond: TimelineScalar = 40
    private let labelWidth: TimelineScalar = 160
    private let minZoomScale: TimelineScalar = 0.5
    private let maxZoomScale: TimelineScalar = 4
    private let zoomStep: TimelineScalar = 0.25
    let minimumTrimDuration: TimeInterval = 0.1

    @State var zoomScale: TimelineScalar = 1
    @State var availableWidth: CGFloat = 800
    @State var selection: RangeSelection?
    @State var dragStartTime: TimeInterval?
    @State var isTrimming = false
    @State var showImportPanel = false
    @State var zoomSuggestions: [ZoomSuggestion] = []
    @State var dismissedSuggestionIds: Set<UUID> = []
    @State var isGeneratingSuggestions = false
    @State var thumbnailTask: Task<Void, Never>?

    @State var thumbnailCache: ThumbnailCache?
    @State var thumbnails: [TimeInterval: NSImage] = [:]
    @State var showThumbnails: Bool = true

    @State var waveforms: [String: [Float]] = [:]
    @State var showWaveforms: Bool = true

    var project: Project { editor.project }

    private var playheadTime: Double { playerViewModel.currentTime }

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
                if track.kind == .overlay {
                    let overlayRows = Self.computeOverlayRows(overlays: track.overlays)
                    VStack(spacing: 4) {
                        ForEach(overlayRows) { row in
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
                                }
                            )
                            .frame(height: trackHeight)
                        }
                    }
                    .frame(width: layout.contentWidth, alignment: .leading)
                } else {
                    timelineTrackContent(for: track, layout: layout)
                        .frame(width: layout.contentWidth, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineTrackContent(for track: TimelineTrack, layout: TimelineLayout) -> some View {
        let trackWaveform = getWaveformForTrack(track.kind)

        if track.kind == .overlay {
            TimelineOverlayTrackRow(
                editor: editor,
                overlays: track.overlays,
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
}
