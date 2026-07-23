//
//  EditorModel+Adjustments.swift
//  EngineKit
//
//  Non-destructive effect ("adjustment") operations and convenience clip-add
//  helpers. All operations mutate clip metadata only; source media is untouched.
//

import Foundation

extension EditorModel {

    // MARK: - Adjustment Operations

    /// Attach an effect to a clip. Returns the updated project.
    public func addAdjustment(
        _ adjustment: Project.Adjustment,
        toClipId clipId: String,
        inTrackId trackId: UUID
    ) async -> EditorResult {
        guard let (trackIndex, clipIndex) = locate(clipId: clipId, trackId: trackId) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }
        let clip = projectRef.timeline.tracks[trackIndex].clips[clipIndex]
        if let error = EditorValidation.validateAdjustment(adjustment, clipDuration: clip.duration) {
            return .failure(error)
        }
        var adjustments = projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments ?? []
        adjustments.append(adjustment)
        projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments = adjustments
        touch()
        return .success(projectRef)
    }

    /// Remove an effect from a clip by its adjustment ID.
    public func removeAdjustment(
        _ adjustmentId: UUID,
        fromClipId clipId: String,
        inTrackId trackId: UUID
    ) async -> EditorResult {
        guard let (trackIndex, clipIndex) = locate(clipId: clipId, trackId: trackId) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }
        var adjustments = projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments ?? []
        adjustments.removeAll { $0.id == adjustmentId }
        projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments = adjustments.isEmpty ? nil : adjustments
        touch()
        return .success(projectRef)
    }

    /// Replace an existing effect (matched by ID) with an updated value.
    public func updateAdjustment(
        _ adjustment: Project.Adjustment,
        inClipId clipId: String,
        trackId: UUID
    ) async -> EditorResult {
        guard let (trackIndex, clipIndex) = locate(clipId: clipId, trackId: trackId) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }
        var adjustments = projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments ?? []
        guard let idx = adjustments.firstIndex(where: { $0.id == adjustment.id }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        let clipDuration = projectRef.timeline.tracks[trackIndex].clips[clipIndex].duration
        if let error = EditorValidation.validateAdjustment(adjustment, clipDuration: clipDuration) {
            return .failure(error)
        }
        adjustments[idx] = adjustment
        projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments = adjustments
        touch()
        return .success(projectRef)
    }

    /// Remove all effects from a clip.
    public func clearAdjustments(clipId: String, inTrackId trackId: UUID) async -> EditorResult {
        guard let (trackIndex, clipIndex) = locate(clipId: clipId, trackId: trackId) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }
        projectRef.timeline.tracks[trackIndex].clips[clipIndex].adjustments = nil
        touch()
        return .success(projectRef)
    }

    // MARK: - Per-clip Audio Mute (recording clips)

    /// Mute/unmute the audio of a recording clip (sets `RecordingClipRef.audioMuted`).
    public func setClipAudioMuted(
        clipId: String,
        inTrackId trackId: UUID,
        muted: Bool
    ) async -> EditorResult {
        guard let (trackIndex, clipIndex) = locate(clipId: clipId, trackId: trackId) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        if projectRef.timeline.tracks[trackIndex].isLocked {
            return .failure(.trackLocked(trackId.uuidString))
        }
        guard case .recording(var ref) = projectRef.timeline.tracks[trackIndex].clips[clipIndex].content else {
            return .failure(.invalidClipContent(reason: "Per-clip audio mute applies only to recording clips"))
        }
        ref.audioMuted = muted
        projectRef.timeline.tracks[trackIndex].clips[clipIndex].content = .recording(ref)
        touch()
        return .success(projectRef)
    }

    // MARK: - Convenience clip-add helpers (one new track per import)

    /// Add a still image as a clip on a new `.video` track.
    public func addImageClip(
        path: String,
        duration: TimeInterval = 5.0,
        at timelineIn: TimeInterval,
        trackName: String = ""
    ) async -> EditorResult {
        let clip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .image(Project.ImageClipRef(path: path, duration: duration))
        )
        if let error = EditorValidation.validateClip(clip) {
            return .failure(error)
        }
        let trackId = projectRef.timeline.addTrack(type: .video, name: trackName)
        return await addClip(clip, toTrackId: trackId)
    }

    /// Add an audio file as a clip on a new `.audio` track.
    public func addAudioClip(
        path: String,
        duration: TimeInterval,
        at timelineIn: TimeInterval,
        sourceIn: TimeInterval = 0,
        trackName: String = ""
    ) async -> EditorResult {
        let clip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .audio(Project.AudioClipRef(path: path, duration: duration, sourceIn: sourceIn))
        )
        if let error = EditorValidation.validateClip(clip) {
            return .failure(error)
        }
        let trackId = projectRef.timeline.addTrack(type: .audio, name: trackName)
        return await addClip(clip, toTrackId: trackId)
    }

    /// Add a solid color card as a clip on a new `.video` track.
    public func addColorClip(
        hexColor: String = "#000000",
        duration: TimeInterval = 3.0,
        at timelineIn: TimeInterval,
        trackName: String = ""
    ) async -> EditorResult {
        let clip = Project.TimelineClip(
            timelineIn: timelineIn,
            content: .color(Project.ColorClipRef(hexColor: hexColor, duration: duration))
        )
        if let error = EditorValidation.validateClip(clip) {
            return .failure(error)
        }
        let trackId = projectRef.timeline.addTrack(type: .video, name: trackName)
        return await addClip(clip, toTrackId: trackId)
    }

    // MARK: - Private helpers

    /// Find the (track, clip) indices for a clip ID on a specific track.
    private func locate(clipId: String, trackId: UUID) -> (Int, Int)? {
        guard let trackIndex = projectRef.timeline.tracks.firstIndex(where: { $0.id == trackId }),
              let clipIndex = projectRef.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId })
        else { return nil }
        return (trackIndex, clipIndex)
    }

    private func touch() {
        projectRef.updatedAt = Date()
    }
}
