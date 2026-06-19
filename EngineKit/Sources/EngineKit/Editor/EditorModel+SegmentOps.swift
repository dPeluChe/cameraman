//
//  EditorModel+SegmentOps.swift
//  EngineKit
//
//  Backward-compatible segment operations on the primary track.
//  Overlay and media item operations.
//

import Foundation

extension EditorModel {

    // MARK: - Segment Operations (backward compatible, delegates to primary track)

    /// Trim the beginning of a segment (adjust sourceIn)
    public func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        return await trimSegment(segmentId: segmentId) { ref in
            guard newSourceIn >= 0 && newSourceIn < ref.sourceOut else {
                return .failure(.invalidTrimTime(sourceIn: newSourceIn, sourceOut: ref.sourceOut, reason: "newSourceIn must be >= 0 and < sourceOut"))
            }
            ref.sourceIn = newSourceIn
            return nil
        }
    }

    /// Trim the end of a segment (adjust sourceOut)
    public func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        return await trimSegment(segmentId: segmentId) { ref in
            guard newSourceOut > ref.sourceIn else {
                return .failure(.invalidTrimTime(sourceIn: ref.sourceIn, sourceOut: newSourceOut, reason: "newSourceOut must be > sourceIn"))
            }
            ref.sourceOut = newSourceOut
            return nil
        }
    }

    /// Shared trim logic: validates primary track, finds clip, applies mutation, adjusts timeline.
    private func trimSegment(
        segmentId: String,
        mutation: (inout Project.RecordingClipRef) -> EditorResult?
    ) async -> EditorResult {
        guard let trackIndex = primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked("primary"))
        }
        guard let clipIndex = projectRef.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        var clip = projectRef.timeline.tracks[trackIndex].clips[clipIndex]
        guard case .recording(var ref) = clip.content else {
            return .failure(.invalidClipContent(reason: "trim only applies to recording clips"))
        }

        let oldDuration = (ref.sourceOut - ref.sourceIn) / clip.speed
        if let error = mutation(&ref) { return error }
        clip.content = .recording(ref)
        let newDuration = (ref.sourceOut - ref.sourceIn) / clip.speed

        updateClipInProject(trackIndex: trackIndex, clipIndex: clipIndex, clip: clip)
        adjustSubsequentClips(trackIndex: trackIndex, from: clipIndex + 1, by: -(oldDuration - newDuration))
        recalculateTimelineDuration()

        return .success(projectRef)
    }

    /// Split a segment into two parts at a specified timeline time
    public func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        guard let trackIndex = primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked("primary"))
        }
        guard let clipIndex = projectRef.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let clip = projectRef.timeline.tracks[trackIndex].clips[clipIndex]
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

        replaceClipInProject(trackIndex: trackIndex, clipIndex: clipIndex, with: [firstClip, secondClip])
        recalculateTimelineDuration()

        return .successWithInfo(projectRef, .splitCreated(newSegmentId: secondClip.id))
    }

    /// Add a new segment to the timeline (recording clip to primary track)
    public func addSegment(
        takeId: UUID,
        sourceIn: TimeInterval,
        sourceOut: TimeInterval,
        timelineIn: TimeInterval
    ) async -> EditorResult {
        if let trackIndex = primaryTrackIndex,
           projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked("primary"))
        }
        guard projectRef.takes.contains(where: { $0.id == takeId }) else {
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

        ensurePrimaryTrack()
        let trackIndex = primaryTrackIndex!
        appendAndSortClip(newClip, trackIndex: trackIndex)
        recalculateTimelineDuration()

        return .successWithInfo(projectRef, .segmentAdded(segmentId: newClip.id))
    }

    /// Delete a segment from the timeline
    public func delete(segmentId: String) async -> EditorResult {
        guard let trackIndex = primaryTrackIndex else {
            return .failure(.trackNotFound("primary"))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked("primary"))
        }
        guard let clipIndex = projectRef.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let clip = projectRef.timeline.tracks[trackIndex].clips[clipIndex]
        let duration = clip.duration

        removeClipFromProject(trackIndex: trackIndex, clipIndex: clipIndex)
        adjustSubsequentClips(trackIndex: trackIndex, from: clipIndex, by: -duration)
        recalculateTimelineDuration()

        return .success(projectRef)
    }

    /// Ripple-delete a timeline range across every (unlocked) track: clips inside
    /// the range are removed, clips overlapping it are trimmed/split, and clips
    /// after it shift left so all tracks stay in sync.
    public func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        guard startTime < endTime else {
            return .failure(.invalidRange(start: startTime, end: endTime))
        }

        var totalAffected = 0
        for trackIndex in projectRef.timeline.tracks.indices
        where !projectRef.timeline.tracks[trackIndex].isLocked {
            totalAffected += deleteRangeInTrack(trackIndex: trackIndex, startTime: startTime, endTime: endTime)
        }
        recalculateTimelineDuration()

        return .successWithInfo(projectRef, .rangeDeleted(count: totalAffected))
    }

    /// Apply the range deletion to a single track; returns the number of clips
    /// removed or replaced. Pure clip math, so it works for any clip content type.
    private func deleteRangeInTrack(trackIndex: Int, startTime: TimeInterval, endTime: TimeInterval) -> Int {
        var clipsToDelete: [String] = []
        var clipsToReplace: [(id: String, replacements: [Project.TimelineClip])] = []
        let rangeWidth = endTime - startTime

        for clip in projectRef.timeline.tracks[trackIndex].clips {
            let clipEnd = clip.timelineOut

            if clip.timelineIn >= startTime && clipEnd <= endTime {
                clipsToDelete.append(clip.id)
            } else if clip.timelineIn < startTime && clipEnd > endTime {
                let preOffset = startTime - clip.timelineIn
                let postOffset = endTime - clip.timelineIn
                let (preContent, _) = splitContent(clip.content, at: preOffset, speed: clip.speed)
                let (_, postContent) = splitContent(clip.content, at: postOffset, speed: clip.speed)

                clipsToReplace.append((id: clip.id, replacements: [
                    Project.TimelineClip(timelineIn: clip.timelineIn, content: preContent, speed: clip.speed, volume: clip.volume, opacity: clip.opacity, position: clip.position),
                    Project.TimelineClip(timelineIn: endTime, content: postContent, speed: clip.speed, volume: clip.volume, opacity: clip.opacity, position: clip.position)
                ]))
            } else if clip.timelineIn < startTime && clipEnd > startTime && clipEnd <= endTime {
                let preOffset = startTime - clip.timelineIn
                let (preContent, _) = splitContent(clip.content, at: preOffset, speed: clip.speed)
                clipsToReplace.append((id: clip.id, replacements: [
                    Project.TimelineClip(timelineIn: clip.timelineIn, content: preContent, speed: clip.speed, volume: clip.volume, opacity: clip.opacity, position: clip.position)
                ]))
            } else if clip.timelineIn >= startTime && clip.timelineIn < endTime && clipEnd > endTime {
                let postOffset = endTime - clip.timelineIn
                let (_, postContent) = splitContent(clip.content, at: postOffset, speed: clip.speed)
                clipsToReplace.append((id: clip.id, replacements: [
                    Project.TimelineClip(timelineIn: endTime, content: postContent, speed: clip.speed, volume: clip.volume, opacity: clip.opacity, position: clip.position)
                ]))
            }
        }

        applyClipReplacements(clipsToReplace, trackIndex: trackIndex)
        deleteClipsByIds(clipsToDelete, trackIndex: trackIndex)
        shiftClipsAfter(startTime, by: -rangeWidth, trackIndex: trackIndex)
        return clipsToDelete.count + clipsToReplace.count
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
        guard let index = projectRef.overlays.firstIndex(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        var overlay = projectRef.overlays[index]

        if let newTransform = transform { overlay.transform = newTransform }
        if let newStyle = style { overlay.style = newStyle }
        if let newStart = start { overlay.start = newStart }
        if let newEnd = end { overlay.end = newEnd }
        if let newAnimation = animation { overlay.animation = newAnimation }

        guard overlay.start < overlay.end else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Start time must be less than end time"))
        }

        guard overlay.start >= 0 && overlay.end <= projectRef.timeline.duration else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Overlay timing must be within timeline duration"))
        }

        updateOverlayInProject(index: index, overlay: overlay)

        return .success(projectRef)
    }

    /// Delete an overlay
    public func deleteOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async -> EditorResult {
        guard projectRef.overlays.contains(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        removeOverlayFromProject(overlayId: overlayId)

        return .success(projectRef)
    }

    // MARK: - Media Item Operations (legacy compatibility)

    /// Add an imported media item to the project
    public func addMediaItem(_ item: Project.MediaItem) async -> EditorResult {
        appendMediaItem(item)
        return .successWithInfo(projectRef, .mediaItemAdded(mediaItemId: item.id))
    }

    /// Remove a media item from the project
    public func removeMediaItem(id: UUID) async -> EditorResult {
        guard projectRef.mediaItems.contains(where: { $0.id == id }) else {
            return .failure(.mediaItemNotFound(id.uuidString))
        }
        removeMediaItemFromProject(id: id)
        return .success(projectRef)
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
        guard let index = projectRef.mediaItems.firstIndex(where: { $0.id == id }) else {
            return .failure(.mediaItemNotFound(id.uuidString))
        }

        updateMediaItemInProject(
            index: index,
            timelineIn: timelineIn, duration: duration,
            volume: volume, opacity: opacity,
            position: position, isMuted: isMuted, name: name
        )

        return .success(projectRef)
    }
}
