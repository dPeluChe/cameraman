//
//  EditorModel.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// Non-destructive editing model for timeline segments
/// All operations modify segments without affecting source media
public actor EditorModel {
    /// The project being edited
    private var project: Project

    /// Initialize with a project
    /// - Parameter project: The project to edit
    public init(project: Project) {
        self.project = project
    }

    /// Get the current project state
    /// - Returns: The edited project
    public func getProject() -> Project {
        return project
    }

    /// Update the project (for loading a different project)
    /// - Parameter project: The new project to edit
    public func setProject(_ project: Project) {
        self.project = project
    }

    // MARK: - Segment Operations

    /// Trim the beginning of a segment (adjust sourceIn)
    /// - Parameters:
    ///   - segmentId: The ID of the segment to trim
    ///   - newSourceIn: The new source in time (must be < current sourceOut)
    /// - Returns: Result indicating success or failure
    public func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        var segment = project.timeline.segments[index]
        guard newSourceIn >= 0 && newSourceIn < segment.sourceOut else {
            return .failure(.invalidTrimTime(
                sourceIn: newSourceIn,
                sourceOut: segment.sourceOut,
                reason: "newSourceIn must be >= 0 and < sourceOut"
            ))
        }

        // Calculate the duration difference to adjust subsequent segments
        let oldDuration = (segment.sourceOut - segment.sourceIn) / segment.speed
        let newDuration = (segment.sourceOut - newSourceIn) / segment.speed
        let durationDelta = oldDuration - newDuration

        segment.sourceIn = newSourceIn
        project.timeline.segments[index] = segment

        // Adjust timeline positions of subsequent segments
        adjustSubsequentSegments(from: index + 1, by: -durationDelta)

        recalculateTimelineDuration()

        return .success(project)
    }

    /// Trim the end of a segment (adjust sourceOut)
    /// - Parameters:
    ///   - segmentId: The ID of the segment to trim
    ///   - newSourceOut: The new source out time (must be > current sourceIn)
    /// - Returns: Result indicating success or failure
    public func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        var segment = project.timeline.segments[index]
        guard newSourceOut > segment.sourceIn else {
            return .failure(.invalidTrimTime(
                sourceIn: segment.sourceIn,
                sourceOut: newSourceOut,
                reason: "newSourceOut must be > sourceIn"
            ))
        }

        // Calculate the duration difference to adjust subsequent segments
        let oldDuration = (segment.sourceOut - segment.sourceIn) / segment.speed
        let newDuration = (newSourceOut - segment.sourceIn) / segment.speed
        let durationDelta = oldDuration - newDuration

        segment.sourceOut = newSourceOut
        project.timeline.segments[index] = segment

        // Adjust timeline positions of subsequent segments
        adjustSubsequentSegments(from: index + 1, by: -durationDelta)

        recalculateTimelineDuration()

        return .success(project)
    }

    /// Split a segment into two parts at a specified timeline time
    /// - Parameters:
    ///   - segmentId: The ID of the segment to split
    ///   - timelineTime: The timeline time at which to split (must be within the segment)
    /// - Returns: Result indicating success or failure, with the new segment ID
    public func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let segment = project.timeline.segments[index]
        guard timelineTime > segment.timelineIn && timelineTime < (segment.timelineIn + (segment.sourceOut - segment.sourceIn) / segment.speed) else {
            return .failure(.invalidSplitTime(
                segmentId: segmentId,
                timelineIn: segment.timelineIn,
                timelineOut: segment.timelineIn + (segment.sourceOut - segment.sourceIn) / segment.speed,
                requestedTime: timelineTime
            ))
        }

        // Calculate the split point in source time
        let timelineOffset = timelineTime - segment.timelineIn
        let sourceSplitTime = segment.sourceIn + (timelineOffset * segment.speed)

        // Create the first segment (from original sourceIn to split point)
        let firstSegment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: segment.sourceIn,
            sourceOut: sourceSplitTime,
            timelineIn: segment.timelineIn,
            speed: segment.speed
        )

        // Create the second segment (from split point to original sourceOut)
        let secondSegment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: sourceSplitTime,
            sourceOut: segment.sourceOut,
            timelineIn: timelineTime,
            speed: segment.speed
        )

        // Replace the original segment with the two new segments
        project.timeline.segments.remove(at: index)
        project.timeline.segments.insert(secondSegment, at: index)
        project.timeline.segments.insert(firstSegment, at: index)

        recalculateTimelineDuration()

        return .successWithInfo(project, .splitCreated(newSegmentId: secondSegment.id))
    }

    /// Add a new segment to the timeline
    /// - Parameters:
    ///   - takeId: The ID of the take to add
    ///   - sourceIn: Start time in the source
    ///   - sourceOut: End time in the source
    ///   - timelineIn: Start time on the timeline
    /// - Returns: Result indicating success or failure
    public func addSegment(
        takeId: UUID,
        sourceIn: TimeInterval,
        sourceOut: TimeInterval,
        timelineIn: TimeInterval
    ) async -> EditorResult {
        // Verify take exists
        guard project.takes.contains(where: { $0.id == takeId }) else {
            return .failure(.takeNotFound(takeId.uuidString))
        }

        let newSegment = Project.Timeline.Segment(
            takeId: takeId,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            timelineIn: timelineIn
        )

        project.timeline.segments.append(newSegment)
        // Sort segments by timeline position
        project.timeline.segments.sort { $0.timelineIn < $1.timelineIn }

        recalculateTimelineDuration()

        return .successWithInfo(project, .segmentAdded(segmentId: newSegment.id))
    }

    /// Delete a segment from the timeline
    /// - Parameter segmentId: The ID of the segment to delete
    /// - Returns: Result indicating success or failure
    public func delete(segmentId: String) async -> EditorResult {
        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            return .failure(.segmentNotFound(segmentId))
        }

        let segment = project.timeline.segments[index]
        let duration = (segment.sourceOut - segment.sourceIn) / segment.speed

        // Remove the segment
        project.timeline.segments.remove(at: index)

        // Adjust timeline positions of subsequent segments
        adjustSubsequentSegments(from: index, by: -duration)

        recalculateTimelineDuration()

        return .success(project)
    }

    /// Delete all segments within a timeline time range
    /// - Parameters:
    ///   - startTime: Start of the range to delete
    ///   - endTime: End of the range to delete
    /// - Returns: Result indicating success or failure, with count of deleted segments
    public func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        guard startTime < endTime else {
            return .failure(.invalidRange(start: startTime, end: endTime))
        }

        var segmentsToDelete: [String] = []
        var segmentsToModify: [(index: Int, segment: Project.Timeline.Segment, newTimelineIn: TimeInterval)] = []
        var offsetAdjustment: TimeInterval = 0

        // Find segments to delete or split
        for (index, segment) in project.timeline.segments.enumerated() {
            let segmentEnd = segment.timelineIn + (segment.sourceOut - segment.sourceIn) / segment.speed

            // Segment is completely within the delete range
            if segment.timelineIn >= startTime && segmentEnd <= endTime {
                segmentsToDelete.append(segment.id)
            }
            // Segment starts before and ends within the range
            else if segment.timelineIn < startTime && segmentEnd > startTime && segmentEnd <= endTime {
                let timelineOffset = startTime - segment.timelineIn
                let sourceSplitTime = segment.sourceIn + (timelineOffset * segment.speed)
                let newDuration = (segment.sourceOut - sourceSplitTime) / segment.speed
                segmentsToModify.append((index, segment, startTime + newDuration))
            }
            // Segment starts within and ends after the range
            else if segment.timelineIn >= startTime && segment.timelineIn < endTime && segmentEnd > endTime {
                let timelineOffset = endTime - segment.timelineIn
                let sourceSplitTime = segment.sourceIn + (timelineOffset * segment.speed)
                let newDuration = (segment.sourceOut - sourceSplitTime) / segment.speed
                offsetAdjustment += (endTime - startTime)
                segmentsToModify.append((index, segment, endTime))
            }
            // Segment spans the entire delete range (start before, end after)
            else if segment.timelineIn < startTime && segmentEnd > endTime {
                // Need to split this segment into two parts
                let firstOffset = startTime - segment.timelineIn
                let firstSourceSplit = segment.sourceIn + (firstOffset * segment.speed)
                let firstEnd = startTime

                let secondOffset = endTime - segment.timelineIn
                let secondSourceSplit = segment.sourceIn + (secondOffset * segment.speed)
                let secondStart = segment.timelineIn

                let firstPart = Project.Timeline.Segment(
                    id: UUID().uuidString,
                    sourceIn: segment.sourceIn,
                    sourceOut: firstSourceSplit,
                    timelineIn: segment.timelineIn,
                    speed: segment.speed
                )

                let secondPart = Project.Timeline.Segment(
                    id: UUID().uuidString,
                    sourceIn: secondSourceSplit,
                    sourceOut: segment.sourceOut,
                    timelineIn: secondStart,
                    timelineOut: firstEnd + (segmentEnd - endTime),
                    speed: segment.speed
                )

                segmentsToDelete.append(segment.id)
                offsetAdjustment += (endTime - startTime)

                // We'll need special handling for this case
                // For now, delete the original and mark for special processing
            }
        }

        // Delete segments
        for segmentId in segmentsToDelete {
            if let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) {
                let segment = project.timeline.segments[index]
                let duration = (segment.sourceOut - segment.sourceIn) / segment.speed
                project.timeline.segments.remove(at: index)
                offsetAdjustment += duration
            }
        }

        // Adjust all remaining segments
        let currentSegments = project.timeline.segments
        var runningAdjustment: TimeInterval = 0

        for (index, segment) in currentSegments.enumerated() {
            if segment.timelineIn >= startTime {
                project.timeline.segments[index].timelineIn -= offsetAdjustment
            }
        }

        recalculateTimelineDuration()

        return .successWithInfo(project, .rangeDeleted(count: segmentsToDelete.count))
    }

    // MARK: - Helper Methods

    /// Adjust the timeline positions of segments starting from a given index
    /// - Parameters:
    ///   - startIndex: The index to start adjusting from
    ///   - delta: The time delta to add (positive or negative)
    private func adjustSubsequentSegments(from startIndex: Int, by delta: TimeInterval) {
        guard startIndex < project.timeline.segments.count else { return }

        for i in startIndex..<project.timeline.segments.count {
            project.timeline.segments[i].timelineIn += delta
        }
    }

    /// Recalculate the total timeline duration based on all segments
    private func recalculateTimelineDuration() {
        var maxEnd: TimeInterval = 0

        for segment in project.timeline.segments {
            let segmentEnd = segment.timelineIn + (segment.sourceOut - segment.sourceIn) / segment.speed
            maxEnd = max(maxEnd, segmentEnd)
        }

        // Update the timeline duration (need to create a new Timeline since it's a let property)
        let newTimeline = Project.Timeline(
            duration: maxEnd,
            segments: project.timeline.segments
        )
        project.timeline = newTimeline
    }

    // MARK: - Overlay Operations

    /// Update an overlay's transform, style, or timing
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - overlayId: The overlay ID to update
    ///   - transform: New transform (optional)
    ///   - style: New style (optional)
    ///   - start: New start time (optional)
    ///   - end: New end time (optional)
    /// - Returns: Result indicating success or failure
    public func updateOverlay(
        projectId: ProjectId,
        overlayId: UUID,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        animation: Project.Overlay.Animation? = nil
    ) async -> EditorResult {
        guard let index = project.overlays.firstIndex(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        var overlay = project.overlays[index]

        if let newTransform = transform {
            overlay.transform = newTransform
        }

        if let newStyle = style {
            overlay.style = newStyle
        }

        if let newStart = start {
            overlay.start = newStart
        }

        if let newEnd = end {
            overlay.end = newEnd
        }

        if let newAnimation = animation {
            overlay.animation = newAnimation
        }

        // Validate timing constraints
        guard overlay.start < overlay.end else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Start time must be less than end time"))
        }

        guard overlay.start >= 0 && overlay.end <= project.timeline.duration else {
            return .failure(.invalidTrimTime(sourceIn: overlay.start, sourceOut: overlay.end, reason: "Overlay timing must be within timeline duration"))
        }

        project.overlays[index] = overlay

        // Update project timestamp
        project = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            takes: project.takes,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: project.overlays,
            chapters: project.chapters,
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: Date()
        )

        return .success(project)
    }

    /// Delete an overlay
    /// - Parameters:
    ///   - projectId: The project ID
    ///   - overlayId: The overlay ID to delete
    /// - Returns: Result indicating success or failure
    public func deleteOverlay(
        projectId: ProjectId,
        overlayId: UUID
    ) async -> EditorResult {
        guard project.overlays.contains(where: { $0.id == overlayId }) else {
            return .failure(.segmentNotFound(overlayId.uuidString))
        }

        project.overlays.removeAll { $0.id == overlayId }

        // Update project timestamp
        project = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            takes: project.takes,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: project.overlays,
            chapters: project.chapters,
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: Date()
        )

        return .success(project)
    }
}

// MARK: - Editor Result Types

/// Result of an editing operation
public enum EditorResult: Equatable {
    case success(Project)
    case successWithInfo(Project, EditorResultInfo)
    case failure(EditorError)

    /// Get the project from a successful result
    public func getProject() -> Project? {
        switch self {
        case .success(let project):
            return project
        case .successWithInfo(let project, _):
            return project
        case .failure:
            return nil
        }
    }
}

/// Additional information about the result
public enum EditorResultInfo: Equatable {
    case splitCreated(newSegmentId: String)
    case rangeDeleted(count: Int)
    case segmentAdded(segmentId: String)
}

/// Errors that can occur during editing operations
public enum EditorError: Error, Equatable {
    case segmentNotFound(String)
    case takeNotFound(String)
    case invalidTrimTime(sourceIn: TimeInterval, sourceOut: TimeInterval, reason: String)
    case invalidSplitTime(segmentId: String, timelineIn: TimeInterval, timelineOut: TimeInterval, requestedTime: TimeInterval)
    case invalidRange(start: TimeInterval, end: TimeInterval)
    case emptyTimeline
    case insufficientMedia

    /// Localized description of the error
    public var localizedDescription: String {
        switch self {
        case .segmentNotFound(let id):
            return "Segment with ID '\(id)' not found"
        case .takeNotFound(let id):
            return "Take with ID '\(id)' not found in project"
        case .invalidTrimTime(let sourceIn, let sourceOut, let reason):
            return "Invalid trim: sourceIn=\(sourceIn)s, sourceOut=\(sourceOut)s - \(reason)"
        case .invalidSplitTime(let id, let timelineIn, let timelineOut, let requestedTime):
            return "Invalid split time for segment '\(id)': requested=\(requestedTime)s, must be between \(timelineIn)s and \(timelineOut)s"
        case .invalidRange(let start, let end):
            return "Invalid range: start(\(start)s) must be less than end(\(end)s)"
        case .emptyTimeline:
            return "Cannot perform operation on empty timeline"
        case .insufficientMedia:
            return "Not enough media to perform operation"
        }
    }
}

// MARK: - Convenience Extensions

extension Project.Timeline.Segment {
    /// Calculate the duration of this segment on the timeline
    public var timelineDuration: TimeInterval {
        (sourceOut - sourceIn) / speed
    }

    /// Calculate the end time of this segment on the timeline
    public var timelineOut: TimeInterval {
        timelineIn + timelineDuration
    }

    /// Initialize with timelineOut for convenience
    public init(
        id: String,
        sourceIn: TimeInterval,
        sourceOut: TimeInterval,
        timelineIn: TimeInterval,
        timelineOut: TimeInterval,
        speed: Double
    ) {
        self.id = id
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.timelineIn = timelineIn
        self.speed = speed
    }
}
