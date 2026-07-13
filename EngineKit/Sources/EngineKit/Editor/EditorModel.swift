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
        self.project.timeline.ensurePrimaryTrack()
    }

    /// Get the current project state
    public func getProject() -> Project {
        return project
    }

    /// Update the project (for loading a different project)
    public func setProject(_ project: Project) {
        self.project = project
        self.project.timeline.ensurePrimaryTrack()
    }

    // MARK: - Track Operations

    /// Add a new track to the timeline
    public func addTrack(type: Project.TrackType, name: String = "") async -> EditorResult {
        let trackId = project.timeline.addTrack(type: type, name: name)
        project.updatedAt = Date()
        return .successWithInfo(project, .trackAdded(trackId: trackId))
    }

    /// Import a video file as a clip on its own new `.video` track (one row per
    /// import). Single operation so callers get one undo step.
    public func importVideoClip(
        path: String,
        duration: TimeInterval,
        at timelineIn: TimeInterval,
        trackName: String = ""
    ) async -> EditorResult {
        let trackId = project.timeline.addTrack(type: .video, name: trackName)
        let clip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .video(Project.VideoClipRef(path: path, sourceOut: duration))
        )
        return await addClip(clip, toTrackId: trackId)
    }

    /// Import an audio file as a clip on a new `.audio` track. Used for
    /// voiceover recordings and imported audio. Single operation = one undo step.
    public func importAudioClip(
        path: String,
        duration: TimeInterval,
        at timelineIn: TimeInterval,
        trackName: String = "Voiceover"
    ) async -> EditorResult {
        let trackId = project.timeline.addTrack(type: .audio, name: trackName)
        let clip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .audio(Project.AudioClipRef(path: path, duration: duration))
        )
        return await addClip(clip, toTrackId: trackId)
    }

    /// Swap a .video track with its nearest .video neighbor (up = earlier in the
    /// array). Order matters twice: row order in the timeline UI and compositing
    /// z-order (later tracks render on top).
    public func moveVideoTrack(trackId: UUID, up: Bool) async -> EditorResult {
        let videoIndices = project.timeline.tracks.indices.filter {
            project.timeline.tracks[$0].type == .video
        }
        guard let position = videoIndices.firstIndex(where: {
            project.timeline.tracks[$0].id == trackId
        }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        if project.timeline.tracks[videoIndices[position]].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }

        let neighborPosition = up ? position - 1 : position + 1
        guard videoIndices.indices.contains(neighborPosition) else {
            // Already first/last — nothing to do, not an error
            return .successWithInfo(project, .trackMoved(trackId: trackId))
        }

        project.timeline.tracks.swapAt(videoIndices[position], videoIndices[neighborPosition])
        project.updatedAt = Date()
        return .successWithInfo(project, .trackMoved(trackId: trackId))
    }

    /// Remove a track from the timeline by ID
    public func removeTrack(trackId: UUID) async -> EditorResult {
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            return .failure(.trackNotFound(trackId.uuidString))
        }
        if project.timeline.tracks[index].type == .primary {
            return .failure(.invalidTrackType(expected: "non-primary", got: "primary"))
        }
        if project.timeline.tracks[index].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
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

        // A non-primary track with no clips left is a ghost: invisible in the
        // UI but still in the array, where it corrupts neighbor-based actions
        // (e.g. "place after track above" reading its end as 0).
        if project.timeline.tracks[trackIndex].clips.isEmpty,
           project.timeline.tracks[trackIndex].type != .primary {
            project.timeline.tracks.remove(at: trackIndex)
        }

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
        if project.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
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
        if project.timeline.tracks[fromIndex].isLocked {
            return .failure(.trackLocked(fromTrackId.uuidString))
        }
        if project.timeline.tracks[toIndex].isLocked {
            return .failure(.trackLocked(toTrackId.uuidString))
        }

        var clip = project.timeline.tracks[fromIndex].clips[clipIndex]

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
        if project.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
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

        // Both halves inherit the parent's effects. Adjustment time windows are
        // clip-relative; whole-clip adjustments (the common case) carry over
        // cleanly, time-windowed ones keep their original offsets.
        let firstClip = Project.TimelineClip(
            timelineIn: clip.timelineIn, content: firstContent,
            speed: clip.speed, volume: clip.volume, opacity: clip.opacity,
            position: clip.position, adjustments: clip.adjustments
        )
        let secondClip = Project.TimelineClip(
            timelineIn: timelineTime, content: secondContent,
            speed: clip.speed, volume: clip.volume, opacity: clip.opacity,
            position: clip.position, adjustments: clip.adjustments
        )

        replaceClipInProject(trackIndex: trackIndex, clipIndex: clipIndex, with: [firstClip, secondClip])
        recalculateTimelineDuration()
        project.updatedAt = Date()

        return .successWithInfo(project, .splitCreated(newSegmentId: secondClip.id))
    }

    // MARK: - Internal Accessors (for extension files)

    var projectRef: Project {
        get { project }
        set { project = newValue }
    }

    var primaryTrackIndex: Int? {
        project.timeline.primaryTrackIndex
    }

    func ensurePrimaryTrack() {
        project.timeline.ensurePrimaryTrack()
    }

    // MARK: - Internal Mutation Helpers

    func adjustSubsequentClips(trackIndex: Int, from startIndex: Int, by delta: TimeInterval) {
        guard startIndex < project.timeline.tracks[trackIndex].clips.count else { return }
        for i in startIndex..<project.timeline.tracks[trackIndex].clips.count {
            project.timeline.tracks[trackIndex].clips[i].timelineIn += delta
        }
    }

    func recalculateTimelineDuration() {
        var maxEnd: TimeInterval = 0
        for track in project.timeline.tracks {
            for clip in track.clips {
                maxEnd = max(maxEnd, clip.timelineOut)
            }
        }
        for overlay in project.overlays {
            maxEnd = max(maxEnd, overlay.end)
        }
        for item in project.mediaItems {
            maxEnd = max(maxEnd, item.timelineOut)
        }
        project.timeline.duration = maxEnd
    }

    func updateClipInProject(trackIndex: Int, clipIndex: Int, clip: Project.TimelineClip) {
        project.timeline.tracks[trackIndex].clips[clipIndex] = clip
    }

    func replaceClipInProject(trackIndex: Int, clipIndex: Int, with clips: [Project.TimelineClip]) {
        project.timeline.tracks[trackIndex].clips.remove(at: clipIndex)
        for (offset, clip) in clips.enumerated() {
            project.timeline.tracks[trackIndex].clips.insert(clip, at: clipIndex + offset)
        }
    }

    func removeClipFromProject(trackIndex: Int, clipIndex: Int) {
        project.timeline.tracks[trackIndex].clips.remove(at: clipIndex)
    }

    func appendAndSortClip(_ clip: Project.TimelineClip, trackIndex: Int) {
        project.timeline.tracks[trackIndex].clips.append(clip)
        project.timeline.tracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
    }

    func applyClipReplacements(_ replacements: [(id: String, replacements: [Project.TimelineClip])], trackIndex: Int) {
        for replacement in replacements {
            if let idx = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == replacement.id }) {
                replaceClipInProject(trackIndex: trackIndex, clipIndex: idx, with: replacement.replacements)
            }
        }
    }

    func deleteClipsByIds(_ ids: [String], trackIndex: Int) {
        let idsToRemove = Set(ids)
        project.timeline.tracks[trackIndex].clips.removeAll { idsToRemove.contains($0.id) }
    }

    func shiftClipsAfter(_ time: TimeInterval, by delta: TimeInterval, trackIndex: Int) {
        for i in 0..<project.timeline.tracks[trackIndex].clips.count {
            if project.timeline.tracks[trackIndex].clips[i].timelineIn >= time {
                project.timeline.tracks[trackIndex].clips[i].timelineIn += delta
            }
        }
    }

    func updateOverlayInProject(index: Int, overlay: Project.Overlay) {
        project.overlays[index] = overlay
        project.updatedAt = Date()
    }

    func removeOverlayFromProject(overlayId: UUID) {
        project.overlays.removeAll { $0.id == overlayId }
        project.updatedAt = Date()
    }

    func appendMediaItem(_ item: Project.MediaItem) {
        project.mediaItems.append(item)
        project.updatedAt = Date()
    }

    func removeMediaItemFromProject(id: UUID) {
        project.mediaItems.removeAll { $0.id == id }
        project.updatedAt = Date()
    }

    func updateMediaItemInProject(
        index: Int,
        timelineIn: TimeInterval?, duration: TimeInterval?,
        volume: Double?, opacity: Double?,
        position: Project.MediaPosition?, isMuted: Bool?, name: String?
    ) {
        if let t = timelineIn { project.mediaItems[index].timelineIn = t }
        if let d = duration { project.mediaItems[index].duration = d }
        if let v = volume { project.mediaItems[index].volume = v }
        if let o = opacity { project.mediaItems[index].opacity = o }
        if let p = position { project.mediaItems[index].position = p }
        if let m = isMuted { project.mediaItems[index].isMuted = m }
        if let n = name { project.mediaItems[index].name = n }
        project.updatedAt = Date()
    }

    // MARK: - Validation

    private func validateClipForTrack(clip: Project.TimelineClip, track: Project.TimelineTrack) -> EditorError? {
        switch track.type {
        case .primary:
            if case .audio = clip.content {
                return .invalidClipContent(reason: "Primary track does not accept audio clips")
            }
            return nil
        case .video:
            switch clip.content {
            case .image, .video, .color: return nil
            default: return .invalidClipContent(reason: "Video track only accepts image, video, or color clips")
            }
        case .audio:
            if case .audio = clip.content { return nil }
            return .invalidClipContent(reason: "Audio track only accepts audio clips")
        }
    }

    /// Split clip content at a given offset, returning two new content values
    func splitContent(
        _ content: Project.ClipContent,
        at offset: TimeInterval,
        speed: Double
    ) -> (Project.ClipContent, Project.ClipContent) {
        switch content {
        case .recording(let ref):
            let sourceSplit = ref.sourceIn + (offset * speed)
            return (
                .recording(Project.RecordingClipRef(takeId: ref.takeId, sourceIn: ref.sourceIn, sourceOut: sourceSplit, zoom: ref.zoom, cameraPosition: ref.cameraPosition, audioMuted: ref.audioMuted)),
                .recording(Project.RecordingClipRef(takeId: ref.takeId, sourceIn: sourceSplit, sourceOut: ref.sourceOut, zoom: ref.zoom, cameraPosition: ref.cameraPosition, audioMuted: ref.audioMuted))
            )
        case .video(let ref):
            let sourceSplit = ref.sourceIn + (offset * speed)
            return (.video(Project.VideoClipRef(path: ref.path, sourceIn: ref.sourceIn, sourceOut: sourceSplit)),
                    .video(Project.VideoClipRef(path: ref.path, sourceIn: sourceSplit, sourceOut: ref.sourceOut)))
        case .image(let ref):
            return (.image(Project.ImageClipRef(path: ref.path, duration: offset)),
                    .image(Project.ImageClipRef(path: ref.path, duration: ref.duration - offset)))
        case .audio(let ref):
            let sourceOffset = offset * speed
            return (.audio(Project.AudioClipRef(path: ref.path, duration: sourceOffset, sourceIn: ref.sourceIn)),
                    .audio(Project.AudioClipRef(path: ref.path, duration: ref.duration - sourceOffset, sourceIn: ref.sourceIn + sourceOffset)))
        case .color(let ref):
            return (.color(Project.ColorClipRef(hexColor: ref.hexColor, duration: offset)),
                    .color(Project.ColorClipRef(hexColor: ref.hexColor, duration: ref.duration - offset)))
        }
    }
}
