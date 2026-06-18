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
