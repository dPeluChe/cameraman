//
//  ProjectEditor+Subtitles.swift
//  App
//
//  Subtitle operations: generate from a transcript, edit per-cue text/timing,
//  restyle, and clear. Subtitles live in `project.subtitles` as text overlays;
//  all mutations follow the snapshot → setEditorProject → recordUndo → autosave
//  pattern used by the other ProjectEditor extensions.
//

import Foundation
import EngineKit

extension ProjectEditor {
    /// A single transcript line used to seed subtitles.
    struct TranscriptCue {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Replace all subtitles with cues generated from the given transcript lines,
    /// using the current `project.subtitleStyle`. Long lines are split into
    /// shorter, time-apportioned cues so each rendered line fits on screen.
    /// - Returns: number of subtitle cues created.
    @discardableResult
    func generateSubtitles(from cues: [TranscriptCue]) async -> Int {
        let previousProject = project
        var updatedProject = project
        let count = updatedProject.setSubtitles(
            fromSegments: cues.map { (text: $0.text, start: $0.start, end: $0.end) }
        )
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        scheduleAutosave()
        return count
    }

    /// Add a single empty subtitle cue at the given time window.
    @discardableResult
    func addSubtitle(text: String, start: TimeInterval, end: TimeInterval) async -> UUID {
        let overlay = Project.Overlay.subtitle(
            text: text,
            start: start,
            end: max(start + 0.5, end),
            style: project.subtitleStyle
        )
        await mutateSubtitles { $0.append(overlay) }
        return overlay.id
    }

    /// Update a subtitle cue's text and/or timing, keeping its style/identity.
    @discardableResult
    func updateSubtitle(
        id: UUID,
        text: String? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil
    ) async -> Bool {
        await mutateSubtitles { subtitles in
            guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
            if let text { subtitles[index].style.text = text }
            if let start { subtitles[index].start = max(0, start) }
            if let end { subtitles[index].end = end }
            if subtitles[index].end <= subtitles[index].start {
                subtitles[index].end = subtitles[index].start + 0.5
            }
        }
    }

    /// Override an individual cue's typography color and/or vertical position.
    @discardableResult
    func styleSubtitle(
        id: UUID,
        textColor: String? = nil,
        verticalPosition: Double? = nil
    ) async -> Bool {
        await mutateSubtitles { subtitles in
            guard let index = subtitles.firstIndex(where: { $0.id == id }) else { return }
            if let textColor {
                subtitles[index].style.color = textColor
                subtitles[index].style.stroke = textColor
            }
            if let verticalPosition {
                subtitles[index].transform.y = min(max(0, verticalPosition), 1)
            }
        }
    }

    /// Delete a single subtitle cue.
    @discardableResult
    func deleteSubtitle(id: UUID) async -> Bool {
        await mutateSubtitles { $0.removeAll { $0.id == id } }
    }

    /// Remove every subtitle cue.
    @discardableResult
    func clearSubtitles() async -> Bool {
        guard !project.subtitles.isEmpty else { return false }
        return await mutateSubtitles { $0.removeAll() }
    }

    /// Update the default subtitle style and re-derive every existing cue from it
    /// (preserving text, timing, and identity). One undo step.
    @discardableResult
    func setSubtitleStyle(_ style: Project.SubtitleStyle) async -> Bool {
        let previousProject = project
        var updatedProject = project
        updatedProject.subtitleStyle = style
        updatedProject.subtitles = updatedProject.subtitles.map { $0.restyledAsSubtitle(with: style) }
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        scheduleAutosave()
        return true
    }

    // MARK: - Helper

    @discardableResult
    private func mutateSubtitles(_ mutate: (inout [Project.Overlay]) -> Void) async -> Bool {
        let previousProject = project
        var updatedProject = project
        mutate(&updatedProject.subtitles)
        updatedProject.updatedAt = Date()

        await setEditorProject(updatedProject)
        recordUndo(previousProject)
        project = updatedProject
        scheduleAutosave()
        return true
    }
}
