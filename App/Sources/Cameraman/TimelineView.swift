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
//    - TimelineView+Toolbar.swift      (toolbar row, segment inspector)
//    - TimelineView+Tracks.swift       (track content, pinned labels)
//    - TimelineView+Subviews.swift     (playhead, trim handles, markers)
//    - TimelineTrackRow.swift          (single track row rendering)
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
    @State var showVoiceoverPanel = false
    @StateObject var voiceoverVM = VoiceoverRecordingViewModel()
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

    var canZoomIn: Bool {
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
        .overlay(alignment: .topTrailing) {
            if showVoiceoverPanel {
                VoiceoverPanelView(
                    viewModel: voiceoverVM,
                    playheadTime: playheadTime,
                    onDismiss: {
                        Task { await voiceoverVM.cancelRecording() }
                        showVoiceoverPanel = false
                    }
                )
                .padding(.trailing, 8)
                .padding(.top, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showVoiceoverPanel)
        .onDisappear {
            Task { await voiceoverVM.cancelRecording() }
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

}
