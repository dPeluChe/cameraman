//
//  EditorModelTypes.swift
//  EngineKit
//
//  Extracted from EditorModel.swift — result types, errors, and convenience extensions
//

import Foundation

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
    case mediaItemAdded(mediaItemId: UUID)
}

/// Errors that can occur during editing operations
public enum EditorError: Error, Equatable {
    case segmentNotFound(String)
    case mediaItemNotFound(String)
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
        case .mediaItemNotFound(let id):
            return "Media item with ID '\(id)' not found"
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
