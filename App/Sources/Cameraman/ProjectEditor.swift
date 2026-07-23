//
//  ProjectEditor.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Combine
import Foundation
import EngineKit
import SwiftUI

/// UI-friendly wrapper around EditorModel actor.
@MainActor
final class ProjectEditor: ObservableObject {
    private let editorModel: EditorModel
    @Published var project: Project
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    // Snapshot-based undo (Command pattern is prepared for future migration)
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    private let historyLimit = 50
    private var autosaveTask: Task<Void, Never>?

    init(project: Project) {
        self.project = project
        self.editorModel = EditorModel(project: project)
        updateHistoryState()
    }

    /// Schedule a debounced autosave (called after edits)
    /// Shows a brief toast notification when save completes
    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled, let self else { return }
            do {
                try await ProjectLibrary.shared.updateProject(self.project)
                await MainActor.run {
                    self.showAutosaveToast = true
                }
            } catch {
                LogError(.editor, "[AUTOSAVE] Failed: \(error.localizedDescription)")
            }
        }
    }

    @Published var showAutosaveToast = false

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

    /// Toggle the synthetic cursor flag while preserving undo history.
    @discardableResult
    func setSyntheticCursorEnabled(_ enabled: Bool) async -> Bool {
        let previousProject = project
        var updatedProject = project
        var config = updatedProject.syntheticCursor ?? .default
        config.enabled = enabled
        updatedProject.syntheticCursor = config
        await editorModel.setProject(updatedProject)
        project = updatedProject
        recordUndoSnapshot(previousProject)
        scheduleAutosave()
        return true
    }


    func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        await performEdit { await self.editorModel.trimIn(segmentId: segmentId, newSourceIn: newSourceIn) }
    }

    func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        await performEdit { await self.editorModel.trimOut(segmentId: segmentId, newSourceOut: newSourceOut) }
    }

    func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        await performEdit { await self.editorModel.split(segmentId: segmentId, at: timelineTime) }
    }

    func addSegment(takeId: UUID, sourceIn: TimeInterval, sourceOut: TimeInterval, timelineIn: TimeInterval) async -> EditorResult {
        await performEdit {
            await self.editorModel.addSegment(
                takeId: takeId,
                sourceIn: sourceIn,
                sourceOut: sourceOut,
                timelineIn: timelineIn
            )
        }
    }

    /// Import a video as a clip on its own new video track (one undo step).
    func importVideoClip(path: String, duration: TimeInterval, at timelineIn: TimeInterval, trackName: String = "") async -> EditorResult {
        await performEdit {
            await self.editorModel.importVideoClip(path: path, duration: duration, at: timelineIn, trackName: trackName)
        }
    }

    /// Import an audio file as a clip on its own new audio track (one undo step).
    func importAudioClip(path: String, duration: TimeInterval, at timelineIn: TimeInterval, trackName: String = "Voiceover") async -> EditorResult {
        await performEdit {
            await self.editorModel.importAudioClip(path: path, duration: duration, at: timelineIn, trackName: trackName)
        }
    }

    /// Update a clip on a timeline track — move, trim (via content), reposition.
    func updateClip(
        clipId: String,
        inTrackId trackId: UUID,
        timelineIn: TimeInterval? = nil,
        volume: Double? = nil,
        position: Project.MediaPosition? = nil,
        content: Project.ClipContent? = nil
    ) async -> EditorResult {
        await performEdit {
            await self.editorModel.updateClip(
                clipId: clipId,
                inTrackId: trackId,
                timelineIn: timelineIn,
                volume: volume,
                position: position,
                content: content
            )
        }
    }

    /// Split a clip on a timeline track at a timeline position (one undo step).
    func splitClip(clipId: String, inTrackId trackId: UUID, at timelineTime: TimeInterval) async -> EditorResult {
        await performEdit {
            await self.editorModel.splitClip(clipId: clipId, inTrackId: trackId, at: timelineTime)
        }
    }

    /// Add a per-clip effect (color filter, blur, audio pitch) — one undo step.
    func addAdjustment(_ adjustment: Project.Adjustment, toClipId clipId: String, inTrackId trackId: UUID) async -> EditorResult {
        await performEdit {
            await self.editorModel.addAdjustment(adjustment, toClipId: clipId, inTrackId: trackId)
        }
    }

    /// Update a clip effect's value (e.g. slider drag) by its id.
    func updateAdjustment(_ adjustment: Project.Adjustment, inClipId clipId: String, trackId: UUID) async -> EditorResult {
        await performEdit {
            await self.editorModel.updateAdjustment(adjustment, inClipId: clipId, trackId: trackId)
        }
    }

    /// Remove a clip effect by its id.
    func removeAdjustment(_ id: UUID, fromClipId clipId: String, inTrackId trackId: UUID) async -> EditorResult {
        await performEdit {
            await self.editorModel.removeAdjustment(id, fromClipId: clipId, inTrackId: trackId)
        }
    }

    /// Reorder a video track among its siblings (also changes compositing z-order).
    func moveVideoTrack(trackId: UUID, up: Bool) async -> EditorResult {
        await performEdit {
            await self.editorModel.moveVideoTrack(trackId: trackId, up: up)
        }
    }

    /// Mute/unmute a timeline track (persists in the project, unlike UI-only mutes).
    func setTrackMuted(trackId: UUID, muted: Bool) async -> EditorResult {
        await performEdit {
            await self.editorModel.setTrackMuted(trackId: trackId, muted: muted)
        }
    }

    /// Remove a clip from a timeline track.
    func removeClip(clipId: String, fromTrackId trackId: UUID) async -> EditorResult {
        await performEdit {
            await self.editorModel.removeClip(clipId: clipId, fromTrackId: trackId)
        }
    }

    func delete(segmentId: String) async -> EditorResult {
        await performEdit { await self.editorModel.delete(segmentId: segmentId) }
    }

    func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        await performEdit { await self.editorModel.deleteRange(from: startTime, to: endTime) }
    }

    /// Snapshot current project, run an EditorModel operation, then propagate the
    /// result + undo snapshot. Centralizes the trim/split/add/delete pattern.
    private func performEdit(_ op: () async -> EditorResult) async -> EditorResult {
        let previousProject = project
        let result = await op()
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


    private func updatePublishedProject(from result: EditorResult, previousProject: Project) {
        if let updatedProject = result.getProject() {
            // Create a generic command for the change - for now use a simple approach
            // TODO: Convert each editorModel method to return a command
            recordUndoSnapshot(previousProject)
            project = updatedProject
            scheduleAutosave()
        }
    }

    // MARK: - Command Pattern (prepared for future migration)

    /// Placeholder for future Command Pattern migration
    /// Currently using snapshot-based undo for compatibility with EditorModel
    /// The EditCommand protocol is defined and ready for migration
    /// TODO: Migrate individual update methods to use commands instead of snapshots

    // MARK: - Internal helpers for extensions

    /// Set the editor model project (used by extensions)
    func setEditorProject(_ updatedProject: Project) async {
        await editorModel.setProject(updatedProject)
    }

    /// Record an undo snapshot (used by extensions)
    func recordUndo(_ snapshot: Project) {
        recordUndoSnapshot(snapshot)
    }

    /// Update published project from an editor result (used by extensions)
    func updateFromResult(_ result: EditorResult, previousProject: Project) {
        updatePublishedProject(from: result, previousProject: previousProject)
    }

    /// Perform overlay update via editor model (used by extensions)
    func performUpdateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        transform: Project.Overlay.Transform?,
        style: Project.Overlay.Style?,
        start: TimeInterval?,
        end: TimeInterval?,
        animation: Project.Overlay.Animation?
    ) async -> EditorResult {
        await editorModel.updateOverlay(
            projectId: projectId,
            overlayId: overlayId,
            transform: transform,
            style: style,
            start: start,
            end: end,
            animation: animation
        )
    }

    /// Perform overlay delete via editor model (used by extensions)
    func performAddOverlay(
        projectId: ProjectId,
        overlay: Project.Overlay
    ) async -> EditorResult {
        await editorModel.addOverlay(projectId: projectId, overlay: overlay)
    }

    func performDeleteOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async -> EditorResult {
        await editorModel.deleteOverlay(
            projectId: projectId,
            overlayId: overlayId
        )
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func recordUndoSnapshot(_ project: Project) {
        undoStack.append(project)
        if undoStack.count > historyLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateHistoryState()
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
