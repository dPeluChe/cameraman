//
//  EditorModel.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// Non-destructive editing model for multi-track timeline.
/// All operations modify tracks and clips without affecting source media.
public actor EditorModel {
    /// The project being edited
    private var project: Project

    /// Initialize with a project
    /// - Parameter project: The project to edit
    public init(project: Project) {
        self.project = project
        // Ensure the timeline has a primary track
        self.project.timeline.ensurePrimaryTrack()
    }

    /// Get the current project state
    /// - Returns: The edited project
    public func getProject() -> Project {
        return project
    }

    /// Update the project (for loading a different project)
    /// - Parameter project: The new project to edit
    public func setProject(_ project: Project) {
        self.project = project
        self.project.timeline.ensurePrimaryTrack()
    }

    // MARK: - Segment Operations (backward compatible, delegates to primary track)

    /// Trim the beginning of a segment (adjust sourceIn)
    public func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        guard let trackIndex = project.timeline.primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        var clip = project.timeline.tracks[trackIndex].clips[clipIndex]
        guard case .recording(var ref) = clip.content else {
            return .failure(.invalidClipContent(reason: "trimIn only applies to recording clips"))
        }

        guard newSourceIn >= 0 && newSourceIn < ref.sourceOut else {
            return .failure(.invalidTrimTime(
                sourceIn: newSourceIn,
                sourceOut: ref.sourceOut,
                reason: "newSourceIn must be >= 0 and < sourceOut"
            ))
        }

        let oldDuration = (ref.sourceOut - ref.sourceIn) / clip.speed
        ref.sourceIn = newSourceIn
        clip.content = .recording(ref)
        let newDuration = (ref.sourceOut - ref.sourceIn) / clip.speed
        let durationDelta = oldDuration - newDuration

        project.timeline.tracks[trackIndex].clips[clipIndex] = clip

        adjustSubsequentClips(trackIndex: trackIndex, from: clipIndex + 1, by: -durationDelta)
        recalculateTimelineDuration()

        return .success(project)
    }

    /// Trim the end of a segment (adjust sourceOut)
    public func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        guard let trackIndex = project.timeline.primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        var clip = project.timeline.tracks[trackIndex].clips[clipIndex]
        guard case .recording(var ref) = clip.content else {
            return .failure(.invalidClipContent(reason: "trimOut only applies to recording clips"))
        }

        guard newSourceOut > ref.sourceIn else {
            return .failure(.invalidTrimTime(
                sourceIn: ref.sourceIn,
                sourceOut: newSourceOut,
                reason: "newSourceOut must be > sourceIn"
            ))
        }

        let oldDuration = (ref.sourceOut - ref.sourceIn) / clip.speed
        ref.sourceOut = newSourceOut
        clip.content = .recording(ref)
        let newDuration = (ref.sourceOut - ref.sourceIn) / clip.speed
        let durationDelta = oldDuration - newDuration

        project.timeline.tracks[trackIndex].clips[clipIndex] = clip

        adjustSubsequentClips(trackIndex: trackIndex, from: clipIndex + 1, by: -durationDelta)
        recalculateTimelineDuration()

        return .success(project)
    }

    /// Split a segment into two parts at a specified timeline time
    public func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        guard let trackIndex = project.timeline.primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let clip = project.timeline.tracks[trackIndex].clips[clipIndex]
        guard case .recording(let ref) = clip.content else {
            return .failure(.invalidClipContent(reason: "split only applies to recording clips"))
        }

        guard timelineTime > clip.timelineIn && timelineTime < clip.timelineOut else {
            return .failure(.invalidSplitTime(
                segmentId: segmentId,
                timelineIn: clip.timelineIn,
                timelineOut: clip.timelineOut,
                requestedTime: timelineTime
            ))
        }

        let timelineOffset = timelineTime - clip.timelineIn
        let sourceSplitTime = ref.sourceIn + (timelineOffset * clip.speed)

        let firstClip = Project.TimelineClip(
            id: UUID().uuidString,
            timelineIn: clip.timelineIn,
            content: .recording(Project.RecordingClipRef(
                takeId: ref.takeId,
                sourceIn: ref.sourceIn,
                sourceOut: sourceSplitTime,
                zoom: ref.zoom,
                cameraPosition: ref.cameraPosition,
                audioMuted: ref.audioMuted
            )),
            speed: clip.speed,
            volume: clip.volume
        )

        let secondClip = Project.TimelineClip(
            id: UUID().uuidString,
            timelineIn: timelineTime,
            content: .recording(Project.RecordingClipRef(
                takeId: ref.takeId,
                sourceIn: sourceSplitTime,
                sourceOut: ref.sourceOut,
                zoom: ref.zoom,
                cameraPosition: ref.cameraPosition,
                audioMuted: ref.audioMuted
            )),
            speed: clip.speed,
            volume: clip.volume
        )

        project.timeline.tracks[trackIndex].clips.remove(at: clipIndex)
        project.timeline.tracks[trackIndex].clips.insert(secondClip, at: clipIndex)
        project.timeline.tracks[trackIndex].clips.insert(firstClip, at: clipIndex)

        recalculateTimelineDuration()

        return .successWithInfo(project, .splitCreated(newSegmentId: secondClip.id))
    }

    /// Add a new segment to the timeline (recording clip to primary track)
    public func addSegment(
        takeId: UUID,
        sourceIn: TimeInterval,
        sourceOut: TimeInterval,
        timelineIn: TimeInterval
    ) async -> EditorResult {
        guard project.takes.contains(where: { $0.id == takeId }) else {
            return .failure(.takeNotFound(takeId.uuidString))
        }

        let newClip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .recording(Project.RecordingClipRef(
                takeId: takeId,
                sourceIn: sourceIn,
                sourceOut: sourceOut
            ))
        )

        project.timeline.ensurePrimaryTrack()
        let trackIndex = project.timeline.primaryTrackIndex!
        project.timeline.tracks[trackIndex].clips.append(newClip)
        project.timeline.tracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }

        recalculateTimelineDuration()

        return .successWithInfo(project, .segmentAdded(segmentId: newClip.id))
    }

    /// Delete a segment from the timeline
    public func delete(segmentId: String) async -> EditorResult {
        guard let trackIndex = project.timeline.primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let clip = project.timeline.tracks[trackIndex].clips[clipIndex]
        let duration = clip.duration

        project.timeline.tracks[trackIndex].clips.remove(at: clipIndex)

        adjustSubsequentClips(trackIndex: trackIndex, from: clipIndex, by: -duration)
        recalculateTimelineDuration()

        return .success(project)
    }

    /// Delete all segments within a timeline time range
    public func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        guard startTime < endTime else {
            return .failure(.invalidRange(start: startTime, end: endTime))
        }
        guard let trackIndex = project.timeline.primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }

        var clipsToDelete: [String] = []
        var offsetAdjustment: TimeInterval = 0

        for clip in project.timeline.tracks[trackIndex].clips {
            let clipEnd = clip.timelineOut

            // Clip is completely within the delete range
            if clip.timelineIn >= startTime && clipEnd <= endTime {
                clipsToDelete.append(clip.id)
            }
            // Clip spans the entire delete range (start before, end after)
            else if clip.timelineIn < startTime && clipEnd > endTime {
                // Split: keep parts outside the range
                if case .recording(let ref) = clip.content {
                    let preOffset = startTime - clip.timelineIn
                    let postOffset = endTime - clip.timelineIn
                    let preSplitSource = ref.sourceIn + (preOffset * clip.speed)
                    let postSplitSource = ref.sourceIn + (postOffset * clip.speed)

                    // Replace with two clips: before range and after range
                    if let idx = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clip.id }) {
                        let preClip = Project.TimelineClip(
                            timelineIn: clip.timelineIn,
                            content: .recording(Project.RecordingClipRef(
                                takeId: ref.takeId,
                                sourceIn: ref.sourceIn,
                                sourceOut: preSplitSource,
                                zoom: ref.zoom,
                                cameraPosition: ref.cameraPosition,
                                audioMuted: ref.audioMuted
                            )),
                            speed: clip.speed,
                            volume: clip.volume
                        )
                        let postClip = Project.TimelineClip(
                            timelineIn: startTime, // will shift after adjustment
                            content: .recording(Project.RecordingClipRef(
                                takeId: ref.takeId,
                                sourceIn: postSplitSource,
                                sourceOut: ref.sourceOut,
                                zoom: ref.zoom,
                                cameraPosition: ref.cameraPosition,
                                audioMuted: ref.audioMuted
                            )),
                            speed: clip.speed,
                            volume: clip.volume
                        )

                        project.timeline.tracks[trackIndex].clips.remove(at: idx)
                        project.timeline.tracks[trackIndex].clips.insert(postClip, at: idx)
                        project.timeline.tracks[trackIndex].clips.insert(preClip, at: idx)
                        offsetAdjustment += (endTime - startTime)
                    }
                    continue
                }
                clipsToDelete.append(clip.id)
                offsetAdjustment += (endTime - startTime)
            }
        }

        // Delete fully-enclosed clips
        for clipId in clipsToDelete {
            if let idx = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) {
                let clip = project.timeline.tracks[trackIndex].clips[idx]
                project.timeline.tracks[trackIndex].clips.remove(at: idx)
                offsetAdjustment += clip.duration
            }
        }

        // Adjust remaining clips after the deleted range
        for i in 0..<project.timeline.tracks[trackIndex].clips.count {
            if project.timeline.tracks[trackIndex].clips[i].timelineIn >= startTime {
                project.timeline.tracks[trackIndex].clips[i].timelineIn -= offsetAdjustment
            }
        }

        recalculateTimelineDuration()

        return .successWithInfo(project, .rangeDeleted(count: clipsToDelete.count))
    }

    // MARK: - Track Operations

    /// Add a new track to the timeline
    public func addTrack(type: Project.TrackType, name: String = "") async -> EditorResult {
        let trackId = project.timeline.addTrack(type: type, name: name)
        project.updatedAt = Date()
        return .successWithInfo(project, .trackAdded(trackId: trackId))
    }

    /// Remove a track from the timeline by ID
    public func removeTrack(trackId: UUID) async -> EditorResult {
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        // Don't allow removing the primary track
        if project.timeline.tracks[index].type == .primary {
            return .failure(.invalidTrackType(expected: "non-primary", got: "primary"))
        }
        project.timeline.tracks.remove(at: index)
        recalculateTimelineDuration()
        project.updatedAt = Date()
        return .successWithInfo(project, .trackRemoved(trackId: trackId))
    }

    /// Toggle track mute state
    public func setTrackMuted(trackId: UUID, muted: Bool) async -> EditorResult {
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        project.timeline.tracks[index].isMuted = muted
        project.updatedAt = Date()
        return .success(project)
    }

    /// Toggle track lock state
    public func setTrackLocked(trackId: UUID, locked: Bool) async -> EditorResult {
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        project.timeline.tracks[index].isLocked = locked
        project.updatedAt = Date()
        return .success(project)
    }

    /// Update track volume
    public func setTrackVolume(trackId: UUID, volume: Double) async -> EditorResult {
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        project.timeline.tracks[index].volume = max(0, min(1, volume))
        project.updatedAt = Date()
        return .success(project)
    }

    // MARK: - Clip Operations (universal, works on any track)

    /// Add a clip to a specific track
    public func addClip(
        _ clip: Project.TimelineClip,
        toTrackId trackId: UUID
    ) async -> EditorResult {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }

        let track = project.timeline.tracks[trackIndex]
        if track.isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }

        // Validate clip content matches track type
        if let error = validateClipForTrack(clip: clip, track: track) {
            return .failure(error)
        }

        project.timeline.tracks[trackIndex].clips.append(clip)
        project.timeline.tracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }

        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .successWithInfo(project, .clipAdded(clipId: clip.id, trackId: trackId))
    }

    /// Remove a clip from a specific track
    public func removeClip(clipId: String, fromTrackId trackId: UUID) async -> EditorResult {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }

        let track = project.timeline.tracks[trackIndex]
        if track.isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }

        guard project.timeline.tracks[trackIndex].clips.contains(where: { $0.id == clipId }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }

        project.timeline.tracks[trackIndex].clips.removeAll { $0.id == clipId }

        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .successWithInfo(project, .clipRemoved(clipId: clipId, trackId: trackId))
    }

    /// Update a clip's properties
    public func updateClip(
        clipId: String,
        inTrackId trackId: UUID,
        timelineIn: TimeInterval? = nil,
        speed: Double? = nil,
        volume: Double? = nil,
        opacity: Double? = nil,
        position: Project.MediaPosition? = nil,
        content: Project.ClipContent? = nil
    ) async -> EditorResult {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }

        if let t = timelineIn { project.timeline.tracks[trackIndex].clips[clipIndex].timelineIn = t }
        if let s = speed { project.timeline.tracks[trackIndex].clips[clipIndex].speed = s }
        if let v = volume { project.timeline.tracks[trackIndex].clips[clipIndex].volume = v }
        if let o = opacity { project.timeline.tracks[trackIndex].clips[clipIndex].opacity = o }
        if let p = position { project.timeline.tracks[trackIndex].clips[clipIndex].position = p }
        if let c = content { project.timeline.tracks[trackIndex].clips[clipIndex].content = c }

        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .success(project)
    }

    /// Move a clip from one track to another
    public func moveClip(
        clipId: String,
        fromTrackId: UUID,
        toTrackId: UUID,
        newTimelineIn: TimeInterval? = nil
    ) async -> EditorResult {
        guard let fromIndex = project.timeline.tracks.firstIndex(where: { $0.id == fromTrackId }) else {
            return .failure(.trackNotFound(fromTrackId.uuidString))
        }
        guard let toIndex = project.timeline.tracks.firstIndex(where: { $0.id == toTrackId }) else {
            return .failure(.trackNotFound(toTrackId.uuidString))
        }
        guard let clipIndex = project.timeline.tracks[fromIndex].clips.firstIndex(where: { $0.id == clipId }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: fromTrackId.uuidString))
        }

        var clip = project.timeline.tracks[fromIndex].clips[clipIndex]

        // Validate clip is compatible with destination track
        if let error = validateClipForTrack(clip: clip, track: project.timeline.tracks[toIndex]) {
            return .failure(error)
        }

        if let newTime = newTimelineIn {
            clip.timelineIn = newTime
        }

        project.timeline.tracks[fromIndex].clips.remove(at: clipIndex)
        project.timeline.tracks[toIndex].clips.append(clip)
        project.timeline.tracks[toIndex].clips.sort { $0.timelineIn < $1.timelineIn }

        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .successWithInfo(project, .clipMoved(clipId: clipId, fromTrackId: fromTrackId, toTrackId: toTrackId))
    }

    /// Split a clip at a given timeline time (works for any clip type in any track)
    public func splitClip(
        clipId: String,
        inTrackId trackId: UUID,
        at timelineTime: TimeInterval
    ) async -> EditorResult {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        guard let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }

        let clip = project.timeline.tracks[trackIndex].clips[clipIndex]

        guard timelineTime > clip.timelineIn && timelineTime < clip.timelineOut else {
            return .failure(.invalidSplitTime(
                segmentId: clipId,
                timelineIn: clip.timelineIn,
                timelineOut: clip.timelineOut,
                requestedTime: timelineTime
            ))
        }

        let offset = timelineTime - clip.timelineIn

        let (firstContent, secondContent) = splitContent(clip.content, at: offset, speed: clip.speed)

        let firstClip = Project.TimelineClip(
            timelineIn: clip.timelineIn,
            content: firstContent,
            speed: clip.speed,
            volume: clip.volume,
            opacity: clip.opacity,
            position: clip.position
        )
        let secondClip = Project.TimelineClip(
            timelineIn: timelineTime,
            content: secondContent,
            speed: clip.speed,
            volume: clip.volume,
            opacity: clip.opacity,
            position: clip.position
        )

        project.timeline.tracks[trackIndex].clips.remove(at: clipIndex)
        project.timeline.tracks[trackIndex].clips.insert(secondClip, at: clipIndex)
        project.timeline.tracks[trackIndex].clips.insert(firstClip, at: clipIndex)

        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .successWithInfo(project, .splitCreated(newSegmentId: secondClip.id))
    }

    // MARK: - Overlay Operations

    /// Update an overlay's transform, style, or timing
    public func updateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        animation: Project.Overlay.Animation? = nil
    ) async -> EditorResult {
        guard let index = project.overlays.firstIndex(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        var overlay = project.overlays[index]

        if let newTransform = transform { overlay.transform = newTransform }
        if let newStyle = style { overlay.style = newStyle }
        if let newStart = start { overlay.start = newStart }
        if let newEnd = end { overlay.end = newEnd }
        if let newAnimation = animation { overlay.animation = newAnimation }

        guard overlay.start < overlay.end else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Start time must be less than end time"))
        }

        guard overlay.start >= 0 && overlay.end <= project.timeline.duration else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Overlay timing must be within timeline duration"))
        }

        project.overlays[index] = overlay
        project.updatedAt = Date()

        return .success(project)
    }

    /// Delete an overlay
    public func deleteOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async -> EditorResult {
        guard project.overlays.contains(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        project.overlays.removeAll { $0.id == overlayId }
        project.updatedAt = Date()

        return .success(project)
    }

    // MARK: - Media Item Operations (legacy compatibility)

    /// Add an imported media item to the project
    public func addMediaItem(_ item: Project.MediaItem) async -> EditorResult {
        project.mediaItems.append(item)
        project.updatedAt = Date()
        return .successWithInfo(project, .mediaItemAdded(mediaItemId: item.id))
    }

    /// Remove a media item from the project
    public func removeMediaItem(id: UUID) async -> EditorResult {
        guard project.mediaItems.contains(where: { $0.id == id }) else {
            return .failure(.mediaItemNotFound(id.uuidString))
        }
        project.mediaItems.removeAll { $0.id == id }
        project.updatedAt = Date()
        return .success(project)
    }

    /// Update a media item's properties
    public func updateMediaItem(
        id: UUID,
        timelineIn: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        volume: Double? = nil,
        opacity: Double? = nil,
        position: Project.MediaPosition? = nil,
        isMuted: Bool? = nil,
        name: String? = nil
    ) async -> EditorResult {
        guard let index = project.mediaItems.firstIndex(where: { $0.id == id }) else {
            return .failure(.mediaItemNotFound(id.uuidString))
        }

        if let t = timelineIn { project.mediaItems[index].timelineIn = t }
        if let d = duration { project.mediaItems[index].duration = d }
        if let v = volume { project.mediaItems[index].volume = v }
        if let o = opacity { project.mediaItems[index].opacity = o }
        if let p = position { project.mediaItems[index].position = p }
        if let m = isMuted { project.mediaItems[index].isMuted = m }
        if let n = name { project.mediaItems[index].name = n }

        project.updatedAt = Date()
        return .success(project)
    }

    // MARK: - Private Helpers

    /// Adjust the timeline positions of clips starting from a given index in a track
    private func adjustSubsequentClips(trackIndex: Int, from startIndex: Int, by delta: TimeInterval) {
        guard startIndex < project.timeline.tracks[trackIndex].clips.count else { return }
        for i in startIndex..<project.timeline.tracks[trackIndex].clips.count {
            project.timeline.tracks[trackIndex].clips[i].timelineIn += delta
        }
    }

    /// Recalculate the total timeline duration from all tracks
    private func recalculateTimelineDuration() {
        var maxEnd: TimeInterval = 0

        for track in project.timeline.tracks {
            if track.isMuted { continue }
            for clip in track.clips {
                maxEnd = max(maxEnd, clip.timelineOut)
            }
        }

        // Also consider overlays and media items
        for overlay in project.overlays {
            maxEnd = max(maxEnd, overlay.end)
        }
        for item in project.mediaItems {
            maxEnd = max(maxEnd, item.timelineOut)
        }

        project.timeline = Project.Timeline(
            duration: maxEnd,
            tracks: project.timeline.tracks
        )
    }

    /// Validate that a clip's content is compatible with the target track type
    private func validateClipForTrack(clip: Project.TimelineClip, track: Project.TimelineTrack) -> EditorError? {
        switch track.type {
        case .primary:
            // Primary track accepts recording, image, video, color
            if case .audio = clip.content {
                return .invalidTrackType(expected: "audio", got: "primary")
            }
            return nil
        case .video:
            // Video tracks accept image, video, color
            switch clip.content {
            case .image, .video, .color:
                return nil
            default:
                return .invalidClipContent(reason: "Video track only accepts image, video, or color clips")
            }
        case .audio:
            // Audio tracks accept audio only
            if case .audio = clip.content {
                return nil
            }
            return .invalidClipContent(reason: "Audio track only accepts audio clips")
        }
    }

    /// Split clip content at a given offset, returning two new content values
    private func splitContent(
        _ content: Project.ClipContent,
        at offset: TimeInterval,
        speed: Double
    ) -> (Project.ClipContent, Project.ClipContent) {
        switch content {
        case .recording(let ref):
            let sourceSplit = ref.sourceIn + (offset * speed)
            let first = Project.RecordingClipRef(
                takeId: ref.takeId, sourceIn: ref.sourceIn, sourceOut: sourceSplit,
                zoom: ref.zoom, cameraPosition: ref.cameraPosition, audioMuted: ref.audioMuted
            )
            let second = Project.RecordingClipRef(
                takeId: ref.takeId, sourceIn: sourceSplit, sourceOut: ref.sourceOut,
                zoom: ref.zoom, cameraPosition: ref.cameraPosition, audioMuted: ref.audioMuted
            )
            return (.recording(first), .recording(second))

        case .video(let ref):
            let sourceSplit = ref.sourceIn + (offset * speed)
            let first = Project.VideoClipRef(path: ref.path, sourceIn: ref.sourceIn, sourceOut: sourceSplit)
            let second = Project.VideoClipRef(path: ref.path, sourceIn: sourceSplit, sourceOut: ref.sourceOut)
            return (.video(first), .video(second))

        case .image(let ref):
            let first = Project.ImageClipRef(path: ref.path, duration: offset)
            let second = Project.ImageClipRef(path: ref.path, duration: ref.duration - offset)
            return (.image(first), .image(second))

        case .audio(let ref):
            let sourceOffset = offset * speed
            let first = Project.AudioClipRef(path: ref.path, duration: offset * speed, sourceIn: ref.sourceIn)
            let second = Project.AudioClipRef(path: ref.path, duration: ref.duration - sourceOffset, sourceIn: ref.sourceIn + sourceOffset)
            return (.audio(first), .audio(second))

        case .color(let ref):
            let first = Project.ColorClipRef(hexColor: ref.hexColor, duration: offset)
            let second = Project.ColorClipRef(hexColor: ref.hexColor, duration: ref.duration - offset)
            return (.color(first), .color(second))
        }
    }
}
