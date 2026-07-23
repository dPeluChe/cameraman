//
//  TimelineView+Tracks.swift
//  App
//
//  Track-content rendering for TimelineView (extracted to keep TimelineView.swift
//  focused on layout/state). Renders the per-track row for non-overlay,
//  non-subtitle kinds (screen, camera, audio, video clips, etc.).
//

import SwiftUI
import EngineKit

extension TimelineView {
    @ViewBuilder
    func timelineTrackContent(for track: TimelineTrack, layout: TimelineLayout) -> some View {
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
                },
                rowLabel: "Overlays",
                showsLabel: false
            )
        } else {
            TimelineTrackRow(
                track: track,
                layout: layout,
                height: trackHeight,
                selectedSegmentId: selectedSegmentId,
                isInteractive: track.kind == .screen,
                isMuted: track.engineTrackId != nil ? track.engineMuted : mutedTracks.contains(track.kind),
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
                    if let trackId = track.engineTrackId {
                        // Per-row mute persisted on the engine track — the shared
                        // kind-based set would mute every imported video row at once.
                        let muted = track.engineMuted
                        Task { _ = await editor.setTrackMuted(trackId: trackId, muted: !muted) }
                    } else if mutedTracks.contains(track.kind) {
                        mutedTracks.remove(track.kind)
                    } else {
                        mutedTracks.insert(track.kind)
                    }
                },
                selectedVideoClipId: selectedVideoClip?.clip.id,
                onVideoClipMoved: { clip, deltaX in
                    guard let trackId = track.engineTrackId else { return }
                    let deltaTime = TimeInterval(deltaX / layout.pixelsPerSecond)
                    Task {
                        let newTimelineIn = max(0, clip.timelineIn + deltaTime)
                        _ = await editor.updateClip(clipId: clip.id, inTrackId: trackId, timelineIn: newTimelineIn)
                    }
                },
                onVideoClipTrimmed: { clip, edge, deltaX in
                    guard let trackId = track.engineTrackId else { return }
                    applyVideoClipTrim(clip: clip, trackId: trackId, edge: edge, deltaX: deltaX, layout: layout)
                },
                onSelectVideoClip: { clip in
                    guard let trackId = track.engineTrackId else { return }
                    if selectedVideoClip?.clip.id == clip.id {
                        selectedVideoClip = nil
                    } else {
                        selectedVideoClip = SelectedVideoClip(clip: clip, trackId: trackId)
                        playerViewModel.seek(to: clip.timelineIn)
                    }
                },
                onVideoClipAction: { clip, action in
                    guard let trackId = track.engineTrackId else { return }
                    handleVideoClipAction(action, clip: clip, trackId: trackId)
                },
                snapClipDeltaX: { clip, deltaX in
                    snappedClipDeltaX(clip: clip, rawDeltaX: deltaX, layout: layout)
                },
                showsLabel: false
            )
        }
    }
}

// MARK: - Track rows & pinned labels (moved from TimelineView.swift)

extension TimelineView {
    /// The pinned label column rendered above the horizontal scroll view.
    func fixedTrackLabels(tracks: [TimelineTrack]) -> some View {
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

    func timelineTracks(layout: TimelineLayout, tracks: [TimelineTrack]) -> some View {
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
