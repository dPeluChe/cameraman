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
    /// Unique identifier for this command
    var id: UUID { get }
    
    /// Human-readable description of the command
    var description: String { get }
    
    /// Execute the command and return the new project state
    func execute(project: Project) async throws -> Project
    
    /// Reverse the command to undo
    func undo(project: Project) async throws -> Project
}

/// Error types for command execution
enum CommandError: Error, LocalizedError {
    case executionFailed(String)
    case undoFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let msg): return "Command execution failed: \(msg)"
        case .undoFailed(let msg): return "Command undo failed: \(msg)"
        }
    }
}

// MARK: - Concrete Commands

/// Command to update camera position in a segment
struct UpdateCameraPositionCommand: EditCommand {
    let id = UUID()
    let description: String
    let segmentId: UUID
    let newPosition: Project.Timeline.CameraPosition
    
    private let oldPosition: Project.Timeline.CameraPosition?
    
    init(segmentId: UUID, newPosition: Project.Timeline.CameraPosition, oldPosition: Project.Timeline.CameraPosition? = nil) {
        self.description = "Update camera position"
        self.segmentId = segmentId
        self.newPosition = newPosition
        self.oldPosition = oldPosition
    }
    
    func execute(project: Project) async throws -> Project {
        var updated = project
        if let segmentIndex = updated.timeline.segments.firstIndex(where: { $0.id == segmentId }) {
            updated.timeline.segments[segmentIndex].cameraPosition = newPosition
        }
        return updated
    }
    
    func undo(project: Project) async throws -> Project {
        var updated = project
        if let segmentIndex = updated.timeline.segments.firstIndex(where: { $0.id == segmentId }),
           let oldPos = oldPosition {
            updated.timeline.segments[segmentIndex].cameraPosition = oldPos
        }
        return updated
    }
}

/// Command to update background
struct UpdateBackgroundCommand: EditCommand {
    let id = UUID()
    let description: String
    let newBackground: Project.Canvas.Background
    let oldBackground: Project.Canvas.Background?
    
    init(newBackground: Project.Canvas.Background, oldBackground: Project.Canvas.Background? = nil) {
        self.description = "Update background"
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
        if let old = oldBackground {
            updated.canvas.background = old
        }
        return updated
    }
}

/// Command to add overlay
struct AddOverlayCommand: EditCommand {
    let id = UUID()
    let description = "Add overlay"
    let overlay: Project.Overlay
    
    func execute(project: Project) async throws -> Project {
        var updated = project
        updated.overlays.append(overlay)
        return updated
    }
    
    func undo(project: Project) async throws -> Project {
        var updated = project
        updated.overlays.removeAll { $0.id == overlay.id }
        return updated
    }
}

/// Command to delete overlay
struct DeleteOverlayCommand: EditCommand {
    let id = UUID()
    let description = "Delete overlay"
    let deletedOverlay: Project.Overlay
    
    func execute(project: Project) async throws -> Project {
        var updated = project
        updated.overlays.removeAll { $0.id == deletedOverlay.id }
        return updated
    }
    
    func undo(project: Project) async throws -> Project {
        var updated = project
        updated.overlays.append(deletedOverlay)
        return updated
    }
}

/// Command to update canvas format
struct UpdateCanvasFormatCommand: EditCommand {
    let id = UUID()
    let description: String
    let newFormat: Project.Canvas.Format
    let oldFormat: Project.Canvas.Format?
    
    init(newFormat: Project.Canvas.Format, oldFormat: Project.Canvas.Format? = nil) {
        self.description = "Update canvas format"
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
        if let old = oldFormat {
            updated.canvas.format = old
        }
        return updated
    }
}