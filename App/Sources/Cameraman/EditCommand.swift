//
//  EditCommand.swift
//  App
//
//  Command Pattern for undo/redo - replaces full project snapshots
//

import Foundation
import EngineKit

/// Protocol for edit commands that can be undone/redone
protocol EditCommand: Sendable {
    var id: UUID { get }
    var description: String { get }
    func execute(project: Project) async throws -> Project
    func undo(project: Project) async throws -> Project
}

/// Generic command that stores full project snapshot for undo
/// This is the baseline implementation - simple and reliable
struct GenericSnapshotCommand: EditCommand {
    let id = UUID()
    let description: String
    let previousProject: Project
    
    init(description: String, previousProject: Project) {
        self.description = description
        self.previousProject = previousProject
    }
    
    func execute(project: Project) async throws -> Project {
        return project // No-op - change applied externally
    }
    
    func undo(project: Project) async throws -> Project {
        return previousProject
    }
}

/// Command to update background (optimized)
struct UpdateBackgroundCommand: EditCommand {
    let id = UUID()
    let description = "Update background"
    let newBackground: Project.Canvas.Background
    let oldBackground: Project.Canvas.Background
    
    init(newBackground: Project.Canvas.Background, oldBackground: Project.Canvas.Background) {
        self.newBackground = newBackground
        self.oldBackground = oldBackground
    }
    
    func execute(project: Project) async throws -> Project {
        var updated = project
        updated.canvas.background = newBackground
        return updated
    }
    
    func undo(project: Project) async throws -> Project {
        var updated = project
        updated.canvas.background = oldBackground
        return updated
    }
}

/// Command to update canvas format (optimized)
struct UpdateCanvasFormatCommand: EditCommand {
    let id = UUID()
    let description = "Update canvas format"
    let newFormat: Project.Canvas.Format
    let oldFormat: Project.Canvas.Format
    
    init(newFormat: Project.Canvas.Format, oldFormat: Project.Canvas.Format) {
        self.newFormat = newFormat
        self.oldFormat = oldFormat
    }
    
    func execute(project: Project) async throws -> Project {
        var updated = project
        updated.canvas.format = newFormat
        return updated
    }
    
    func undo(project: Project) async throws -> Project {
        var updated = project
        updated.canvas.format = oldFormat
        return updated
    }
}