//
//  OverlayEngine.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// OverlayEngine provides CRUD operations for managing overlays in a project
public actor OverlayEngine {
    /// Project store for loading/saving projects
    private let projectStore: ProjectStore

    /// Initialize a new OverlayEngine
    /// - Parameter projectStore: Project store for persistence
    public init(projectStore: ProjectStore = ProjectStore()) {
        self.projectStore = projectStore
    }

    // MARK: - CRUD Operations

    /// Add a new overlay to a project
    /// - Parameters:
    ///   - projectId: Project ID to add overlay to
    ///   - type: Overlay type (arrow, rect, line, text)
    ///   - start: Start time in seconds
    ///   - end: End time in seconds
    ///   - transform: Transform (position, scale, rotation)
    ///   - style: Style configuration
    /// - Returns: Result containing the created overlay's ID
    public func addOverlay(
        projectId: ProjectId,
        type: Project.Overlay.OverlayType,
        start: TimeInterval,
        end: TimeInterval,
        transform: Project.Overlay.Transform,
        style: Project.Overlay.Style
    ) async throws -> OverlayResult {
        // Validate time range
        try validateTimeRange(start: start, end: end)

        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Validate overlay fits within timeline
        try validateOverlayWithinTimeline(start: start, end: end, timelineDuration: project.timeline.duration)

        // Create overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: type,
            start: start,
            end: end,
            transform: transform,
            style: style
        )

        // Add to project
        project.overlays.append(overlay)

        // Save project
        try await projectStore.saveProject(project)

        return .success(overlayId: overlay.id)
    }

    /// Update an existing overlay
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - overlayId: Overlay ID to update
    ///   - type: New overlay type (optional)
    ///   - start: New start time (optional)
    ///   - end: New end time (optional)
    ///   - transform: New transform (optional)
    ///   - style: New style (optional)
    /// - Returns: Result indicating success or failure
    public func updateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        type: Project.Overlay.OverlayType? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil
    ) async throws -> OverlayResult {
        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Find overlay
        guard let index = project.overlays.firstIndex(where: { $0.id == overlayId }) else {
            throw OverlayError.overlayNotFound(overlayId)
        }

        var overlay = project.overlays[index]

        // Validate time range if provided
        if let newStart = start, let newEnd = end {
            try validateTimeRange(start: newStart, end: newEnd)
            try validateOverlayWithinTimeline(start: newStart, end: newEnd, timelineDuration: project.timeline.duration)
        } else if let newStart = start {
            try validateOverlayWithinTimeline(start: newStart, end: overlay.end, timelineDuration: project.timeline.duration)
        } else if let newEnd = end {
            try validateOverlayWithinTimeline(start: overlay.start, end: newEnd, timelineDuration: project.timeline.duration)
        }

        // Update fields if provided
        if let newType = type {
            overlay.type = newType
        }
        if let newStart = start {
            overlay.start = newStart
        }
        if let newEnd = end {
            overlay.end = newEnd
        }
        if let newTransform = transform {
            overlay.transform = newTransform
        }
        if let newStyle = style {
            overlay.style = newStyle
        }

        // Update in project
        project.overlays[index] = overlay

        // Save project
        try await projectStore.saveProject(project)

        return .success(overlayId: overlayId)
    }

    /// Delete an overlay
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - overlayId: Overlay ID to delete
    /// - Returns: Result indicating success or failure
    public func deleteOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async throws -> OverlayResult {
        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Find overlay
        guard let index = project.overlays.firstIndex(where: { $0.id == overlayId }) else {
            throw OverlayError.overlayNotFound(overlayId)
        }

        // Remove overlay
        project.overlays.remove(at: index)

        // Save project
        try await projectStore.saveProject(project)

        return .success(overlayId: overlayId)
    }

    /// Delete all overlays within a time range
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - start: Start of time range
    ///   - end: End of time range
    /// - Returns: Result with count of deleted overlays
    public func deleteOverlaysInRange(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> OverlayRangeResult {
        // Validate time range
        try validateTimeRange(start: start, end: end)

        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Find overlays that overlap with the time range
        let initialCount = project.overlays.count
        project.overlays.removeAll { overlay in
            // Check if overlay overlaps with the range
            return overlay.start < end && overlay.end > start
        }

        let deletedCount = initialCount - project.overlays.count

        // Save project
        try await projectStore.saveProject(project)

        return .success(count: deletedCount)
    }

    /// Get all overlays for a project
    /// - Parameter projectId: Project ID
    /// - Returns: Array of overlays
    public func getOverlays(projectId: ProjectId) async throws -> [Project.Overlay] {
        let project = try await projectStore.loadProject(projectId: projectId)
        return project.overlays.sorted { $0.start < $1.start }
    }

    /// Get overlays within a time range
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - start: Start of time range
    ///   - end: End of time range
    /// - Returns: Array of overlays within the range
    public func getOverlaysInRange(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> [Project.Overlay] {
        // Validate time range
        try validateTimeRange(start: start, end: end)

        let project = try await projectStore.loadProject(projectId: projectId)

        // Filter overlays that overlap with the time range
        return project.overlays.filter { overlay in
            return overlay.start < end && overlay.end > start
        }.sorted { $0.start < $1.start }
    }

    /// Get a specific overlay by ID
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - overlayId: Overlay ID
    /// - Returns: The overlay
    public func getOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async throws -> Project.Overlay {
        let project = try await projectStore.loadProject(projectId: projectId)

        guard let overlay = project.overlays.first(where: { $0.id == overlayId }) else {
            throw OverlayError.overlayNotFound(overlayId)
        }

        return overlay
    }

    /// Duplicate an overlay
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - overlayId: Overlay ID to duplicate
    ///   - timeOffset: Time offset in seconds for the duplicated overlay (default: 0)
    /// - Returns: Result containing the new overlay's ID
    public func duplicateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        timeOffset: TimeInterval = 0
    ) async throws -> OverlayResult {
        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Find overlay
        guard let originalOverlay = project.overlays.first(where: { $0.id == overlayId }) else {
            throw OverlayError.overlayNotFound(overlayId)
        }

        // Create duplicate with new ID and adjusted time
        var newOverlay = originalOverlay
        newOverlay.id = UUID()
        newOverlay.start += timeOffset
        newOverlay.end += timeOffset

        // Validate new time range
        try validateOverlayWithinTimeline(
            start: newOverlay.start,
            end: newOverlay.end,
            timelineDuration: project.timeline.duration
        )

        // Add to project
        project.overlays.append(newOverlay)

        // Save project
        try await projectStore.saveProject(project)

        return .success(overlayId: newOverlay.id)
    }

    // MARK: - Batch Operations

    /// Reorder overlays
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - overlayIds: Array of overlay IDs in desired order
    /// - Returns: Result indicating success
    public func reorderOverlays(
        projectId: ProjectId,
        overlayIds: [UUID]
    ) async throws -> OverlayResult {
        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        // Validate all overlay IDs exist
        let overlayMap = Dictionary(uniqueKeysWithValues: project.overlays.map { ($0.id, $0) })
        for id in overlayIds {
            guard overlayMap[id] != nil else {
                throw OverlayError.overlayNotFound(id)
            }
        }

        // Reorder overlays
        let reorderedOverlays = overlayIds.compactMap { overlayMap[$0] }
        let remainingOverlays = project.overlays.filter { !overlayIds.contains($0.id) }
        project.overlays = reorderedOverlays + remainingOverlays

        // Save project
        try await projectStore.saveProject(project)

        return .success(overlayId: UUID()) // Dummy ID for batch operation
    }

    /// Delete all overlays in a project
    /// - Parameter projectId: Project ID
    /// - Returns: Result with count of deleted overlays
    public func deleteAllOverlays(projectId: ProjectId) async throws -> OverlayRangeResult {
        // Load project
        var project = try await projectStore.loadProject(projectId: projectId)

        let count = project.overlays.count
        project.overlays.removeAll()

        // Save project
        try await projectStore.saveProject(project)

        return .success(count: count)
    }

    // MARK: - Helper Methods

    /// Validate time range (start < end, both non-negative)
    private func validateTimeRange(start: TimeInterval, end: TimeInterval) throws {
        guard start >= 0 else {
            throw OverlayError.invalidTimeRange("Start time cannot be negative")
        }
        guard end > 0 else {
            throw OverlayError.invalidTimeRange("End time must be positive")
        }
        guard start < end else {
            throw OverlayError.invalidTimeRange("Start time must be less than end time")
        }
    }

    /// Validate overlay fits within project timeline
    private func validateOverlayWithinTimeline(
        start: TimeInterval,
        end: TimeInterval,
        timelineDuration: TimeInterval
    ) throws {
        guard start <= timelineDuration else {
            throw OverlayError.overlayOutsideTimeline(
                "Overlay start time (\(start)s) exceeds timeline duration (\(timelineDuration)s)"
            )
        }
        guard end <= timelineDuration else {
            throw OverlayError.overlayOutsideTimeline(
                "Overlay end time (\(end)s) exceeds timeline duration (\(timelineDuration)s)"
            )
        }
    }
}

// MARK: - Result Types

/// Result type for single overlay operations
public enum OverlayResult: Equatable {
    case success(overlayId: UUID)
    case failure(error: OverlayError)
}

/// Result type for batch overlay operations
public enum OverlayRangeResult: Equatable {
    case success(count: Int)
    case failure(error: OverlayError)
}

// MARK: - Error Types

/// Errors specific to overlay operations
public enum OverlayError: Error, Equatable {
    case overlayNotFound(UUID)
    case invalidTimeRange(String)
    case overlayOutsideTimeline(String)
    case projectNotFound(ProjectId)

    public var errorDescription: String? {
        switch self {
        case .overlayNotFound(let id):
            return "Overlay not found: \(id.uuidString)"
        case .invalidTimeRange(let message):
            return "Invalid time range: \(message)"
        case .overlayOutsideTimeline(let message):
            return "Overlay outside timeline: \(message)"
        case .projectNotFound(let id):
            return "Project not found: \(id.uuidString)"
        }
    }
}

// MARK: - Convenience Helpers

extension OverlayEngine {
    /// Create an arrow overlay
    public func addArrowOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 6.0,
        shadow: Bool = true
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .arrow,
            start: start,
            end: end,
            transform: transform,
            style: style
        )
    }

    /// Create a rectangle overlay
    public func addRectOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 4.0,
        shadow: Bool = true
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .rect,
            start: start,
            end: end,
            transform: transform,
            style: style
        )
    }

    /// Create a line overlay
    public func addLineOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 4.0,
        shadow: Bool = true
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(stroke: stroke, strokeWidth: strokeWidth, shadow: shadow)

        return try await addOverlay(
            projectId: projectId,
            type: .line,
            start: start,
            end: end,
            transform: transform,
            style: style
        )
    }

    /// Create a text overlay
    public func addTextOverlay(
        projectId: ProjectId,
        start: TimeInterval,
        end: TimeInterval,
        x: Double,
        y: Double,
        text: String,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        font: String = "SF Pro",
        size: Double = 36.0,
        color: String = "#FFFFFF",
        bg: String? = "rgba(0,0,0,0.4)"
    ) async throws -> OverlayResult {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: scale, rotation: rotation)
        let style = Project.Overlay.Style(
            stroke: "",
            strokeWidth: 0,
            shadow: false,
            font: font,
            size: size,
            color: color,
            bg: bg,
            text: text
        )

        return try await addOverlay(
            projectId: projectId,
            type: .text,
            start: start,
            end: end,
            transform: transform,
            style: style
        )
    }
}
