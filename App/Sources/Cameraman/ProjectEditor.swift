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

    @discardableResult
    func setLayoutPreset(_ preset: CanvasLayout.LayoutPreset) async -> Bool {
        let hasCamera = project.primarySources?.camera != nil
        if preset != .fullscreen && !hasCamera { return false }
        return await applyCanvasUpdate {
            $0.canvas.layout = CanvasLayout.defaultLayout(for: preset)
            if !hasCamera { $0.canvas.layout.camera = nil }
            try CanvasLayout.validateLayout($0.canvas.layout, hasCamera: hasCamera)
        }
    }

    @discardableResult
    func updateCameraPosition(
        _ camera: Project.Canvas.Layout.CameraPosition,
        recordUndoFrom snapshot: Project? = nil
    ) async -> Bool {
        let hasCamera = project.primarySources?.camera != nil
        return await applyCanvasUpdate(saveAfter: true) {
            $0.canvas.layout.camera = camera
            try CanvasLayout.validateLayout($0.canvas.layout, hasCamera: hasCamera)
        }
    }

    @discardableResult
    func setBackgroundType(_ type: CanvasLayout.BackgroundType) async -> Bool {
        let currentFitMode = CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.defaultBackground(for: type, fitMode: currentFitMode)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundColor(_ hexColor: String) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createSolidBackground(hexColor: hexColor)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundImagePath(
        _ imagePath: String,
        fitMode: CanvasLayout.ImageFitMode? = nil
    ) async -> Bool {
        let resolvedFitMode = fitMode ?? CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createImageBackground(imagePath: imagePath, fitMode: resolvedFitMode)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundFitMode(_ fitMode: CanvasLayout.ImageFitMode) async -> Bool {
        guard project.canvas.background.type == CanvasLayout.BackgroundType.image.rawValue else {
            return false
        }
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createImageBackground(
                imagePath: $0.canvas.background.value,
                fitMode: fitMode
            )
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackground(_ background: Project.Canvas.Background) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.background = background
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func setFormat(_ aspectRatio: CanvasLayout.AspectRatio) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.format = CanvasLayout.createFormat(for: aspectRatio)
            try CanvasLayout.validateFormat($0.canvas.format)
        }
    }

    @discardableResult
    private func applyCanvasUpdate(
        saveAfter: Bool = false,
        _ mutation: (inout Project) throws -> Void
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project
        do { try mutation(&updatedProject) } catch { return false }
        await editorModel.setProject(updatedProject)
        project = updatedProject
        recordUndoSnapshot(previousProject)
        if saveAfter { scheduleAutosave() }
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
