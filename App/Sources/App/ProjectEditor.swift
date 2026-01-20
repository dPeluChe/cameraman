//
//  ProjectEditor.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import EngineKit
import SwiftUI

/// UI-friendly wrapper around EditorModel actor.
@MainActor
final class ProjectEditor: ObservableObject {
    private let editorModel: EditorModel
    @Published private(set) var project: Project
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    private let historyLimit = 50

    init(project: Project) {
        self.project = project
        self.editorModel = EditorModel(project: project)
        updateHistoryState()
    }

    func setProject(_ project: Project) async {
        await editorModel.setProject(project)
        self.project = project
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryState()
    }

    func refreshProject() async {
        project = await editorModel.getProject()
    }

    func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        let previousProject = project
        let result = await editorModel.trimIn(segmentId: segmentId, newSourceIn: newSourceIn)
        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        let previousProject = project
        let result = await editorModel.trimOut(segmentId: segmentId, newSourceOut: newSourceOut)
        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        let previousProject = project
        let result = await editorModel.split(segmentId: segmentId, at: timelineTime)
        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func delete(segmentId: String) async -> EditorResult {
        let previousProject = project
        let result = await editorModel.delete(segmentId: segmentId)
        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        let previousProject = project
        let result = await editorModel.deleteRange(from: startTime, to: endTime)
        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func undo() async -> Bool {
        guard let previousProject = undoStack.popLast() else {
            updateHistoryState()
            return false
        }

        redoStack.append(project)
        await editorModel.setProject(previousProject)
        project = previousProject
        updateHistoryState()
        return true
    }

    func redo() async -> Bool {
        guard let nextProject = redoStack.popLast() else {
            updateHistoryState()
            return false
        }

        undoStack.append(project)
        await editorModel.setProject(nextProject)
        project = nextProject
        updateHistoryState()
        return true
    }

    @discardableResult
    func setLayoutPreset(_ preset: CanvasLayout.LayoutPreset) async -> Bool {
        let hasCamera = project.sources.camera != nil
        if preset != .fullscreen && !hasCamera {
            return false
        }

        let previousProject = project
        var updatedProject = project
        updatedProject.canvas.layout = CanvasLayout.defaultLayout(for: preset)
        if !hasCamera {
            updatedProject.canvas.layout.camera = nil
        }

        do {
            try CanvasLayout.validateLayout(updatedProject.canvas.layout, hasCamera: hasCamera)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func updateCameraPosition(
        _ camera: Project.Canvas.Layout.CameraPosition,
        recordUndoFrom snapshot: Project? = nil
    ) async -> Bool {
        let hasCamera = project.sources.camera != nil
        var updatedProject = project
        updatedProject.canvas.layout.camera = camera

        do {
            try CanvasLayout.validateLayout(updatedProject.canvas.layout, hasCamera: hasCamera)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        project = updatedProject

        if let snapshot {
            recordUndoSnapshot(snapshot)
        }

        return true
    }

    @discardableResult
    func setBackgroundType(_ type: CanvasLayout.BackgroundType) async -> Bool {
        let previousProject = project
        var updatedProject = project
        let currentFitMode = CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        updatedProject.canvas.background = CanvasLayout.defaultBackground(for: type, fitMode: currentFitMode)

        do {
            try CanvasLayout.validateBackground(updatedProject.canvas.background)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func updateBackgroundColor(_ hexColor: String) async -> Bool {
        let previousProject = project
        var updatedProject = project
        updatedProject.canvas.background = CanvasLayout.createSolidBackground(hexColor: hexColor)

        do {
            try CanvasLayout.validateBackground(updatedProject.canvas.background)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func updateBackgroundImagePath(
        _ imagePath: String,
        fitMode: CanvasLayout.ImageFitMode? = nil
    ) async -> Bool {
        let previousProject = project
        let resolvedFitMode = fitMode ?? CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        var updatedProject = project
        updatedProject.canvas.background = CanvasLayout.createImageBackground(
            imagePath: imagePath,
            fitMode: resolvedFitMode
        )

        do {
            try CanvasLayout.validateBackground(updatedProject.canvas.background)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func updateBackgroundFitMode(_ fitMode: CanvasLayout.ImageFitMode) async -> Bool {
        guard project.canvas.background.type == CanvasLayout.BackgroundType.image.rawValue else {
            return false
        }

        let previousProject = project
        var updatedProject = project
        updatedProject.canvas.background = CanvasLayout.createImageBackground(
            imagePath: project.canvas.background.value,
            fitMode: fitMode
        )

        do {
            try CanvasLayout.validateBackground(updatedProject.canvas.background)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func updateBackground(_ background: Project.Canvas.Background) async -> Bool {
        let previousProject = project
        var updatedProject = project
        updatedProject.canvas.background = background

        do {
            try CanvasLayout.validateBackground(updatedProject.canvas.background)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    @discardableResult
    func setFormat(_ aspectRatio: CanvasLayout.AspectRatio) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Create new format for the aspect ratio
        updatedProject.canvas.format = CanvasLayout.createFormat(for: aspectRatio)

        do {
            try CanvasLayout.validateFormat(updatedProject.canvas.format)
        } catch {
            return false
        }

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    private func updatePublishedProject(from result: EditorResult, previousProject: Project) {
        if let updatedProject = result.getProject() {
            recordUndoSnapshot(previousProject)
            project = updatedProject
        }
    }

    private func recordUndoSnapshot(_ snapshot: Project) {
        undoStack.append(snapshot)
        if undoStack.count > historyLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateHistoryState()
    }

    // MARK: - Overlay Operations

    func addOverlay(projectId: ProjectId, overlay: Project.Overlay) async -> EditorResult {
        let previousProject = project

        // Directly add to project since EditorModel doesn't have addOverlay
        var updatedProject = project
        updatedProject.overlays.append(overlay)

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
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

        let result = await editorModel.updateOverlay(
            projectId: projectId,
            overlayId: overlayId,
            transform: transform,
            style: style,
            start: start,
            end: end,
            animation: animation
        )

        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    func deleteOverlay(projectId: ProjectId, overlayId: UUID) async -> EditorResult {
        let previousProject = project

        let result = await editorModel.deleteOverlay(
            projectId: projectId,
            overlayId: overlayId
        )

        updatePublishedProject(from: result, previousProject: previousProject)
        return result
    }

    // MARK: - Chapter Management

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

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Update an existing chapter
    /// - Parameters:
    ///   - chapterId: ID of chapter to update
    ///   - title: New title (optional)
    ///   - summary: New summary (optional)
    ///   - keywords: New keywords (optional)
    /// - Returns: true if successful, false otherwise
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

        // Update fields if provided
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

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Delete a chapter from the project
    /// - Parameter chapterId: ID of chapter to delete
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func deleteChapter(chapterId: UUID) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Find and remove the chapter
        guard let index = updatedProject.chapters.firstIndex(where: { $0.id == chapterId }) else {
            return false
        }

        updatedProject.chapters.remove(at: index)
        updatedProject.updatedAt = Date()

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Apply AI-suggested chapters to the project
    /// - Parameter suggestions: Array of chapter suggestions from AI
    /// - Returns: Number of chapters added
    @discardableResult
    func applyChapterSuggestions(from suggestions: [Suggestion]) async -> Int {
        var addedCount = 0

        for suggestion in suggestions where suggestion.type == .createChapter {
            // Extract chapter metadata from suggestion
            let title = suggestion.metadata("title", as: String.self) ?? "Untitled Chapter"
            let summary = suggestion.metadata("summary", as: String.self)
            let keywords = suggestion.metadata("keywords", as: [String].self) ?? []

            // Create chapter
            let chapter = Project.Chapter(
                title: title,
                startTime: suggestion.timelineIn,
                endTime: suggestion.timelineOut,
                summary: summary,
                keywords: keywords
            )

            // Add to project
            if await addChapter(chapter) {
                addedCount += 1
            }
        }

        return addedCount
    }

    // MARK: - Zoom Controls

    /// Update zoom configuration for a specific segment
    /// - Parameters:
    ///   - segmentId: ID of the segment to update
    ///   - configuration: New zoom configuration
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func updateSegmentZoom(
        segmentId: String,
        configuration: Project.Timeline.ZoomConfiguration
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Find and update the segment
        guard let index = updatedProject.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return false
        }

        updatedProject.timeline.segments[index].zoom = configuration
        updatedProject.updatedAt = Date()

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Update zoom configuration for all timeline segments
    /// - Parameter configuration: New zoom configuration to apply to all segments
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func updateAllSegmentsZoom(configuration: Project.Timeline.ZoomConfiguration) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Update all segments
        for index in updatedProject.timeline.segments.indices {
            updatedProject.timeline.segments[index].zoom = configuration
        }

        updatedProject.updatedAt = Date()

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Remove zoom configuration for a specific segment (reverts to defaults)
    /// - Parameter segmentId: ID of the segment to remove configuration from
    /// - Returns: true if successful, false if segment not found
    @discardableResult
    func removeSegmentZoom(segmentId: String) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Find and update the segment
        guard let index = updatedProject.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return false
        }

        // Remove zoom configuration (will use defaults)
        updatedProject.timeline.segments[index].zoom = nil
        updatedProject.updatedAt = Date()

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    /// Enable or disable zoom for all segments
    /// - Parameter enabled: Whether to enable zoom
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func setZoomEnabled(_ enabled: Bool) async -> Bool {
        let configuration: Project.Timeline.ZoomConfiguration
        if enabled {
            configuration = .normal // Use normal intensity when enabling
        } else {
            configuration = .disabled
        }
        return await updateAllSegmentsZoom(configuration: configuration)
    }

    /// Set zoom intensity for all segments (keeps current enabled state)
    /// - Parameter intensity: Zoom intensity preset
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func setZoomIntensity(_ intensity: Project.Timeline.ZoomConfiguration.ZoomIntensity) async -> Bool {
        let previousProject = project
        var updatedProject = project

        // Update all segments with new intensity
        for index in updatedProject.timeline.segments.indices {
            let currentConfig = updatedProject.timeline.segments[index].zoom
            let shouldEnable = currentConfig?.enabled ?? true // Default to enabled

            updatedProject.timeline.segments[index].zoom = Project.Timeline.ZoomConfiguration(
                enabled: intensity == .disabled ? false : shouldEnable,
                intensity: intensity == .disabled ? nil : intensity
            )
        }

        updatedProject.updatedAt = Date()

        await editorModel.setProject(updatedProject)
        recordUndoSnapshot(previousProject)
        project = updatedProject
        return true
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Testing Helpers

    /// Create a mock ProjectEditor for testing/preview
    static func mockProject() throws -> ProjectEditor {
        // Create a mock project with timeline segments
        let project = Project(
            schemaVersion: 1,
            projectId: "mock-project",
            name: "Mock Project",
            tags: ["test"],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "/tmp/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: Project.Timeline(
                duration: 60.0,
                segments: [
                    Project.Timeline.Segment(
                        id: "segment-1",
                        sourceId: "screen",
                        sourceIn: 0.0,
                        sourceOut: 30.0,
                        timelineIn: 0.0,
                        timelineOut: 30.0,
                        speed: 1.0,
                        zoom: .normal
                    ),
                    Project.Timeline.Segment(
                        id: "segment-2",
                        sourceId: "screen",
                        sourceIn: 30.0,
                        sourceOut: 60.0,
                        timelineIn: 30.0,
                        timelineOut: 60.0,
                        speed: 1.0,
                        zoom: .subtle
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000"),
                layout: CanvasLayout.defaultLayout(for: .fullscreen)
            ),
            overlays: [],
            captions: nil,
            chapters: []
        )

        return ProjectEditor(project: project)
    }
}

/// Range selection for timeline editing.
struct RangeSelection: Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }
}
