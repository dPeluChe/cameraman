//
//  ProjectEditor+ManualZoom.swift
//  App
//
//  Manual zoom keyframe CRUD (add/update/remove/clear, live drag + commit).
//  Extracted from ProjectEditor.swift to keep it inside the 400-500 line
//  budget; uses the internal setEditorProject/recordUndo helpers.
//

import Foundation
import EngineKit

extension ProjectEditor {
    // MARK: - Manual Zoom Keyframes

    @discardableResult
    func addManualZoomKeyframe(
        at timestamp: TimeInterval,
        zoomLevel: Double,
        focusX: Double = 0.5,
        focusY: Double = 0.5,
        easing: ZoomPlanGenerator.EasingFunction = .easeInOut
    ) async -> UUID? {
        let previousProject = project
        var updatedProject = project
        let kf = ZoomPlanGenerator.ZoomKeyframe(
            timestamp: timestamp,
            zoomLevel: zoomLevel,
            focusX: focusX,
            focusY: focusY,
            easing: easing,
            isManual: true
        )
        var keyframes = updatedProject.manualZoomKeyframes ?? []
        keyframes.append(kf)
        keyframes.sort { $0.timestamp < $1.timestamp }
        updatedProject.manualZoomKeyframes = keyframes
        await setEditorProject(updatedProject)
        project = updatedProject
        recordUndo(previousProject)
        scheduleAutosave()
        return kf.id
    }

    @discardableResult
    func updateManualZoomKeyframe(
        id: UUID,
        zoomLevel: Double? = nil,
        focusX: Double? = nil,
        focusY: Double? = nil,
        timestamp: TimeInterval? = nil,
        easing: ZoomPlanGenerator.EasingFunction? = nil
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project
        guard var keyframes = updatedProject.manualZoomKeyframes else { return false }
        guard let idx = keyframes.firstIndex(where: { $0.id == id }) else { return false }
        if let z = zoomLevel { keyframes[idx].zoomLevel = z }
        if let fx = focusX { keyframes[idx].focusX = fx }
        if let fy = focusY { keyframes[idx].focusY = fy }
        if let t = timestamp { keyframes[idx].timestamp = t }
        if let e = easing { keyframes[idx].easing = e }
        keyframes.sort { $0.timestamp < $1.timestamp }
        updatedProject.manualZoomKeyframes = keyframes
        await setEditorProject(updatedProject)
        project = updatedProject
        recordUndo(previousProject)
        scheduleAutosave()
        return true
    }

    @discardableResult
    func removeManualZoomKeyframe(id: UUID) async -> Bool {
        let previousProject = project
        var updatedProject = project
        guard var keyframes = updatedProject.manualZoomKeyframes else { return false }
        let before = keyframes.count
        keyframes.removeAll { $0.id == id }
        guard keyframes.count != before else { return false }
        updatedProject.manualZoomKeyframes = keyframes.isEmpty ? nil : keyframes
        await setEditorProject(updatedProject)
        project = updatedProject
        recordUndo(previousProject)
        scheduleAutosave()
        return true
    }

    @discardableResult
    func clearAllManualZoomKeyframes() async -> Bool {
        let previousProject = project
        var updatedProject = project
        guard updatedProject.manualZoomKeyframes != nil else { return false }
        updatedProject.manualZoomKeyframes = nil
        await setEditorProject(updatedProject)
        project = updatedProject
        recordUndo(previousProject)
        scheduleAutosave()
        return true
    }

    /// Live timestamp update during drag — mutates project without
    /// autosave or undo snapshot for smooth dragging.
    func updateManualZoomKeyframeTimestampLive(id: UUID, timestamp: TimeInterval) {
        var updatedProject = project
        guard var keyframes = updatedProject.manualZoomKeyframes else { return }
        guard let idx = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[idx].timestamp = timestamp
        keyframes.sort { $0.timestamp < $1.timestamp }
        updatedProject.manualZoomKeyframes = keyframes
        project = updatedProject
    }

    /// Commit a drag end — saves to model + autosave + undo snapshot.
    func commitManualZoomKeyframeDrag() async {
        await setEditorProject(project)
        scheduleAutosave()
    }
}
