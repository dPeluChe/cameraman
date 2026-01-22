//
//  Project.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// Project model representing a video project
public struct Project: Codable, Equatable {
    /// Schema version for migration support
    public var schemaVersion: Int
    /// Unique identifier
    public let projectId: ProjectId
    /// Project name
    public var name: String
    /// Tags for organization
    public var tags: [String]
    /// Creation timestamp
    public let createdAt: Date
    /// Last update timestamp
    public var updatedAt: Date
    /// Source media information (Legacy/Migration)
    public var sources: Sources?
    /// Collection of takes (V2)
    public var takes: [Take]
    /// Timeline editing model
    public var timeline: Timeline
    /// Canvas layout configuration
    public var canvas: Canvas
    /// Overlays (annotations)
    public var overlays: [Overlay]
    /// Captions configuration
    public var captions: Captions?
    /// Chapter markers for video navigation
    public var chapters: [Chapter]

    /// Helper to access sources from V1 (legacy) or V2 (first take)
    public var primarySources: Sources? {
        sources ?? takes.first?.sources
    }

    public init(
        projectId: ProjectId,
        name: String,
        sources: Sources? = nil,
        takes: [Take] = [],
        timeline: Timeline,
        canvas: Canvas,
        overlays: [Overlay] = [],
        chapters: [Chapter] = [],
        captions: Captions? = nil,
        tags: [String] = [],
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.projectId = projectId
        self.name = name
        self.sources = sources
        self.takes = takes
        self.timeline = timeline
        self.canvas = canvas
        self.overlays = overlays
        self.chapters = chapters
        self.captions = captions
        self.tags = tags
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

}

/// Project summary for library listing
public struct ProjectSummary: Codable, Equatable, Identifiable {
    public let id: ProjectId
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let tags: [String]
    public let duration: TimeInterval
    public let thumbnailPath: String?

    public var projectId: ProjectId {
        id
    }

    public init(
        projectId: ProjectId,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        tags: [String],
        duration: TimeInterval,
        thumbnailPath: String?
    ) {
        self.id = projectId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.duration = duration
        self.thumbnailPath = thumbnailPath
    }
}
