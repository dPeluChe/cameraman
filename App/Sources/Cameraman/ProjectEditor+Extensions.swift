//
//  ProjectEditor+Extensions.swift
//  App
//
//  Extracted from ProjectEditor.swift
//  Overlay, chapter, and zoom operations
//

import Foundation
import EngineKit

// MARK: - Overlay Operations

extension ProjectEditor {
    func addOverlay(projectId: ProjectId, overlay: Project.Overlay) async -> EditorResult {
        let previousProject = project

        // Directly add to project since EditorModel doesn't have addOverlay
        var updatedProject = project
        updatedProject.overlays.append(overlay)

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject

        return .success(project)
    }

    func updateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        animation: Project.Overlay.Animation? = nil
    ) async -> EditorResult {
        let previousProject = project

        let result = await performUpdateOverlay(
            projectId: projectId,
            overlayId: overlayId,
            transform: transform,
            style: style,
            start: start,
            end: end,
            animation: animation
        )

        updateFromResult(result, previousProject: previousProject)
        return result
    }

    func deleteOverlay(projectId: ProjectId, overlayId: UUID) async -> EditorResult {
        let previousProject = project

        let result = await performDeleteOverlay(
            projectId: projectId,
            overlayId: overlayId
        )

        updateFromResult(result, previousProject: previousProject)
        return result
    }
}

// MARK: - Chapter Management

extension ProjectEditor {
    /// Add a chapter marker to the project
    /// - Parameter chapter: Chapter to add
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func addChapter(_ chapter: Project.Chapter) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Add chapter maintaining chronological order
        updatedProject.chapters.append(chapter)
        updatedProject.chapters.sort { $0.startTime < $1.startTime }
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Update an existing chapter
    @discardableResult
    func updateChapter(
        chapterId: UUID,
        title: String? = nil,
        summary: String? = nil,
        keywords: [String]? = nil
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Find and update the chapter
        guard let index = updatedProject.chapters.firstIndex(where: { $0.id == chapterId }) else {
            return false
        }

        if let title = title {
            updatedProject.chapters[index].title = title
        }
        if let summary = summary {
            updatedProject.chapters[index].summary = summary
        }
        if let keywords = keywords {
            updatedProject.chapters[index].keywords = keywords
        }
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Delete a chapter from the project
    @discardableResult
    func deleteChapter(chapterId: UUID) async -> Bool {
        let previousProject = project
        var updatedProject = project

        guard let index = updatedProject.chapters.firstIndex(where: { $0.id == chapterId }) else {
            return false
        }

        updatedProject.chapters.remove(at: index)
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Apply AI-suggested chapters to the project
    @discardableResult
    func applyChapterSuggestions(from suggestions: [Suggestion]) async -> Int {
        var addedCount = 0

        for suggestion in suggestions where suggestion.type == .createChapter {
            let title = suggestion.metadata("title", as: String.self) ?? "Untitled Chapter"
            let summary = suggestion.metadata("summary", as: String.self)
            let keywords = suggestion.metadata("keywords", as: [String].self) ?? []

            let chapter = Project.Chapter(
                title: title,
                startTime: suggestion.timelineIn,
                endTime: suggestion.timelineOut,
                summary: summary,
                keywords: keywords
            )

            if await addChapter(chapter) {
                addedCount += 1
            }
        }

        return addedCount
    }
}

// MARK: - Zoom Controls

extension ProjectEditor {
    /// Update zoom configuration for a specific segment
    @discardableResult
    func updateSegmentZoom(
        segmentId: String,
        configuration: Project.Timeline.ZoomConfiguration
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project

        guard let index = updatedProject.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return false
        }

        updatedProject.timeline.segments[index].zoom = configuration
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Update zoom configuration for all timeline segments
    @discardableResult
    func updateAllSegmentsZoom(configuration: Project.Timeline.ZoomConfiguration) async -> Bool {
        let previousProject = project
        var updatedProject = project

        for index in updatedProject.timeline.segments.indices {
            updatedProject.timeline.segments[index].zoom = configuration
        }

        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Remove zoom configuration for a specific segment (reverts to defaults)
    @discardableResult
    func removeSegmentZoom(segmentId: String) async -> Bool {
        let previousProject = project
        var updatedProject = project

        guard let index = updatedProject.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return false
        }

        updatedProject.timeline.segments[index].zoom = nil
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }

    /// Enable or disable zoom for all segments
    @discardableResult
    func setZoomEnabled(_ enabled: Bool) async -> Bool {
        let configuration: Project.Timeline.ZoomConfiguration
        if enabled {
            configuration = .normal
        } else {
            configuration = .disabled
        }
        return await updateAllSegmentsZoom(configuration: configuration)
    }

    /// Set zoom intensity for all segments (keeps current enabled state)
    @discardableResult
    func setZoomIntensity(_ intensity: Project.Timeline.ZoomConfiguration.ZoomIntensity) async -> Bool {
        let previousProject = project
        var updatedProject = project

        for index in updatedProject.timeline.segments.indices {
            let currentConfig = updatedProject.timeline.segments[index].zoom
            let shouldEnable = currentConfig?.enabled ?? true

            updatedProject.timeline.segments[index].zoom = Project.Timeline.ZoomConfiguration(
                enabled: intensity == .disabled ? false : shouldEnable,
                intensity: intensity == .disabled ? nil : intensity
            )
        }

        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        return true
    }
}

// MARK: - Media Item Operations

extension ProjectEditor {
    func addMediaItem(_ item: Project.MediaItem) async {
        let previousProject = project
        var updatedProject = project
        updatedProject.mediaItems.append(item)
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
    }

    func removeMediaItem(id: UUID) async {
        let previousProject = project
        var updatedProject = project
        updatedProject.mediaItems.removeAll { $0.id == id }
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
    }

    func updateMediaItem(
        id: UUID,
        timelineIn: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        volume: Double? = nil,
        opacity: Double? = nil,
        position: Project.MediaPosition? = nil,
        isMuted: Bool? = nil,
        name: String? = nil
    ) async {
        let previousProject = project
        var updatedProject = project

        guard let index = updatedProject.mediaItems.firstIndex(where: { $0.id == id }) else { return }

        if let t = timelineIn { updatedProject.mediaItems[index].timelineIn = t }
        if let d = duration { updatedProject.mediaItems[index].duration = d }
        if let v = volume { updatedProject.mediaItems[index].volume = v }
        if let o = opacity { updatedProject.mediaItems[index].opacity = o }
        if let p = position { updatedProject.mediaItems[index].position = p }
        if let m = isMuted { updatedProject.mediaItems[index].isMuted = m }
        if let n = name { updatedProject.mediaItems[index].name = n }

        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
    }
}

// MARK: - Per-Segment Operations

extension ProjectEditor {
    @discardableResult
    private func mutateSegment(segmentId: String, _ mutate: (inout Project.Timeline.Segment) -> Void) async -> Bool {
        let previousProject = project
        var updatedProject = project
        guard let index = updatedProject.timeline.segments.firstIndex(where: { $0.id == segmentId }) else { return false }
        mutate(&updatedProject.timeline.segments[index])
        updatedProject.updatedAt = Date()
        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        scheduleAutosave()
        return true
    }

    @discardableResult
    func updateSegmentSpeed(segmentId: String, speed: Double) async -> Bool {
        await mutateSegment(segmentId: segmentId) { $0.speed = max(0.25, min(4.0, speed)) }
    }

    @discardableResult
    func updateSegmentVolume(segmentId: String, volume: Double?) async -> Bool {
        await mutateSegment(segmentId: segmentId) { $0.volume = volume }
    }

    @discardableResult
    func updateSegmentAudioMuted(segmentId: String, muted: Bool?) async -> Bool {
        await mutateSegment(segmentId: segmentId) { $0.audioMuted = muted }
    }

    @discardableResult
    func updateSegmentCameraPosition(segmentId: String, camera: Project.Canvas.Layout.CameraPosition?) async -> Bool {
        await mutateSegment(segmentId: segmentId) { $0.cameraPosition = camera }
    }
}
