//
//  TimelineView+DragDrop.swift
//  App
//
//  Extracted from TimelineView.swift (Phase 1 refactor, v0.5.1).
//  Playhead drag gesture, asset drop handling, file import, trim application.
//

import SwiftUI
import EngineKit
import AVFoundation

extension TimelineView {
    func timelineDragGesture(layout: TimelineLayout) -> some Gesture {
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

    func handleDrop(providers: [NSItemProvider], location: CGPoint, layout: TimelineLayout) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { idString, _ in
                guard let uuidString = idString as? String,
                      let takeId = UUID(uuidString: uuidString) else { return }

                Task { @MainActor in
                    guard let take = self.editor.project.takes.first(where: { $0.id == takeId }) else { return }

                    let dropTime = layout.time(forXPosition: location.x)
                    var duration: TimeInterval = 10.0

                    if let projectDir = self.projectDirectory {
                        let videoPath = projectDir.appendingPathComponent(take.sources.screen.path)
                        let asset = AVURLAsset(url: videoPath)
                        if let assetDuration = try? await asset.load(.duration) {
                            duration = assetDuration.seconds
                        }
                    }

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

    func handleImportedFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first,
              let projectDir = projectDirectory else { return }

        let ext = url.pathExtension.lowercased()
        let isAudio = ["mp3", "wav", "m4a", "aac", "aiff", "flac"].contains(ext)
        let isImage = ["png", "jpg", "jpeg", "heic", "webp", "tiff"].contains(ext)
        let isVideo = ["mp4", "mov", "m4v", "mpg", "mpeg"].contains(ext)
        guard isAudio || isImage || isVideo else { return }

        let fileName = url.lastPathComponent
        let currentPlayhead = playerViewModel.currentTime

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
            if isAudio || isVideo {
                let asset = AVURLAsset(url: destURL)
                if let assetDuration = try? await asset.load(.duration) {
                    duration = assetDuration.seconds
                }
            }

            if isVideo {
                // Imported video gets its own timeline track row (new model)
                _ = await editor.importVideoClip(
                    path: "assets/\(fileName)",
                    duration: duration,
                    at: currentPlayhead,
                    trackName: fileName
                )
                await warnIfBelowCanvasResolution(videoURL: destURL, fileName: fileName)
                return
            }

            let item = Project.MediaItem(
                type: isAudio ? .audio : .image,
                path: "assets/\(fileName)",
                name: fileName,
                timelineIn: currentPlayhead,
                duration: duration
            )

            await editor.addMediaItem(item)
        }
    }

    /// Upscaling looks soft fullscreen; downscaling (bigger than canvas) is fine,
    /// and smaller videos are also fine as PiP — so only warn on the former.
    func warnIfBelowCanvasResolution(videoURL: URL, fileName: String) async {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return }

        let canvas = editor.project.canvas.format
        guard size.width < CGFloat(canvas.w), size.height < CGFloat(canvas.h) else { return }

        await MainActor.run {
            importNotice = "“\(fileName)” is \(Int(size.width))×\(Int(size.height)) and the project canvas is \(canvas.w)×\(canvas.h). Fullscreen it may look soft — as a smaller PiP it will look sharp."
        }
    }

    /// Magnetic snapping for clip drags: when either edge of the moving clip
    /// comes within ~10pt of another clip's edge (any row), the playhead, or 0,
    /// the drag delta locks onto it.
    func snappedClipDeltaX(clip: Project.TimelineClip, rawDeltaX: TimelineScalar, layout: TimelineLayout) -> TimelineScalar {
        let pps = max(layout.pixelsPerSecond, 0.001)
        let rawDelta = TimeInterval(rawDeltaX / pps)
        let threshold = TimeInterval(10 / pps)

        var points: [TimeInterval] = [0, playerViewModel.currentTime]
        for track in editor.project.timeline.videoTracks {
            for other in track.clips where other.id != clip.id {
                points.append(other.timelineIn)
                points.append(other.timelineOut)
            }
        }
        for segment in editor.project.timeline.segments {
            points.append(segment.timelineIn)
            points.append(segment.timelineIn + segment.timelineDuration)
        }

        let start = clip.timelineIn + rawDelta
        let end = clip.timelineOut + rawDelta
        var best: (distance: TimeInterval, delta: TimeInterval)?
        for point in points {
            let startDistance = abs(start - point)
            if startDistance < (best?.distance ?? threshold) {
                best = (startDistance, point - clip.timelineIn)
            }
            let endDistance = abs(end - point)
            if endDistance < (best?.distance ?? threshold) {
                best = (endDistance, point - clip.timelineOut)
            }
        }

        guard let best else { return rawDeltaX }
        return TimelineScalar(best.delta) * pps
    }

    /// Trim an imported video clip from either edge. Leading trim shifts both
    /// sourceIn and timelineIn; trailing trim adjusts sourceOut, clamped to the
    /// real asset duration so AVFoundation never gets an out-of-range insert.
    func applyVideoClipTrim(
        clip: Project.TimelineClip,
        trackId: UUID,
        edge: TimelineTrimEdge,
        deltaX: TimelineScalar,
        layout: TimelineLayout
    ) {
        guard case .video(let ref) = clip.content, let projectDir = projectDirectory else { return }
        let deltaTime = TimeInterval(deltaX / layout.pixelsPerSecond)
        let minDuration: TimeInterval = 0.25

        Task {
            var newRef = ref
            var newTimelineIn: TimeInterval? = nil

            switch edge {
            case .leading:
                let maxIn = ref.sourceOut - minDuration * clip.speed
                let newSourceIn = min(max(0, ref.sourceIn + deltaTime * clip.speed), maxIn)
                newTimelineIn = max(0, clip.timelineIn + (newSourceIn - ref.sourceIn) / clip.speed)
                newRef.sourceIn = newSourceIn
            case .trailing:
                let assetURL = projectDir.appendingPathComponent(ref.path)
                var assetDuration = ref.sourceOut
                if let loaded = try? await AVURLAsset(url: assetURL).load(.duration) {
                    assetDuration = loaded.seconds
                }
                let minOut = ref.sourceIn + minDuration * clip.speed
                newRef.sourceOut = min(max(minOut, ref.sourceOut + deltaTime * clip.speed), assetDuration)
            }

            guard newRef != ref || newTimelineIn != nil else { return }
            _ = await editor.updateClip(
                clipId: clip.id,
                inTrackId: trackId,
                timelineIn: newTimelineIn,
                content: .video(newRef)
            )
        }
    }

    func applyTrim(
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


/// Context-menu actions on an imported-video clip chip.
enum VideoClipAction {
    case jumpToEnd
    case placeAfterPreviousTrack
    case placeAtStart
    case moveRowUp
    case moveRowDown
    case remove
}

extension TimelineView {
    /// Ordering helpers for imported clips: chain a clip after the video row
    /// above it, snap it to the start, jump the playhead, or remove it.
    func handleVideoClipAction(_ action: VideoClipAction, clip: Project.TimelineClip, trackId: UUID) {
        switch action {
        case .jumpToEnd:
            playerViewModel.seek(to: clip.timelineOut)
        case .placeAfterPreviousTrack:
            // Ignore ghost tracks (empty, hidden from the UI) so "above" matches
            // what the user actually sees.
            let videoTracks = editor.project.timeline.videoTracks.filter { !$0.clips.isEmpty }
            guard let index = videoTracks.firstIndex(where: { $0.id == trackId }), index > 0 else { return }
            let previousEnd = videoTracks[index - 1].clips.map(\.timelineOut).max() ?? 0
            Task {
                _ = await editor.updateClip(clipId: clip.id, inTrackId: trackId, timelineIn: previousEnd)
                playerViewModel.seek(to: previousEnd)
            }
        case .placeAtStart:
            Task { _ = await editor.updateClip(clipId: clip.id, inTrackId: trackId, timelineIn: 0) }
        case .moveRowUp:
            Task { _ = await editor.moveVideoTrack(trackId: trackId, up: true) }
        case .moveRowDown:
            Task { _ = await editor.moveVideoTrack(trackId: trackId, up: false) }
        case .remove:
            if selectedVideoClip?.clip.id == clip.id { selectedVideoClip = nil }
            Task { _ = await editor.removeClip(clipId: clip.id, fromTrackId: trackId) }
        }
    }
}

/// A selected imported-video clip plus its engine track id (for updates/removal).
struct SelectedVideoClip: Identifiable, Equatable {
    let clip: Project.TimelineClip
    let trackId: UUID
    var id: String { clip.id }
}
