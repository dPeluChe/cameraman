//
//  OverlayEngineTypes.swift
//  EngineKit
//
//  Extracted from OverlayEngine.swift — result and error types
//

import Foundation

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

/// Errors specific to overlay operations
public enum OverlayError: Error, Equatable {
    case overlayNotFound(UUID)
    case invalidTimeRange(String)
    case overlayOutsideTimeline(String)
    case projectNotFound(ProjectId)
    case invalidAnimation(String)

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
        case .invalidAnimation(let message):
            return "Invalid animation: \(message)"
        }
    }
}
