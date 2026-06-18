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
    /// Subtitles — timed, styled text cues rendered as text overlays. Stored
    /// separately from `overlays` so they can be generated/restyled/cleared as a
    /// group (typically auto-generated from the transcript).
    public var subtitles: [Overlay]
    /// Default styling template for subtitles (color, position, size).
    public var subtitleStyle: SubtitleStyle
    /// Captions configuration
    public var captions: Captions?
    /// Chapter markers for video navigation
    public var chapters: [Chapter]
    /// Imported media assets (audio, images) placed on the timeline
    public var mediaItems: [MediaItem]

    /// Helper to access sources from V1 (legacy) or V2 (first take)
    public var primarySources: Sources? {
        sources ?? takes.first?.sources
    }

    /// Serialized overlay configs ready for the compositor. Includes subtitles
    /// (which are text overlays) so the preview compositor renders them too.
    public var overlayConfigs: [OverlayConfig] {
        (overlays + subtitles).map { OverlayConfig(overlay: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, projectId, name, tags, createdAt, updatedAt
        case sources, takes, timeline, canvas, overlays, subtitles, subtitleStyle, captions, chapters, mediaItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        projectId = try container.decode(ProjectId.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sources = try container.decodeIfPresent(Sources.self, forKey: .sources)
        takes = try container.decodeIfPresent([Take].self, forKey: .takes) ?? []
        timeline = try container.decode(Timeline.self, forKey: .timeline)
        canvas = try container.decode(Canvas.self, forKey: .canvas)
        overlays = try container.decodeIfPresent([Overlay].self, forKey: .overlays) ?? []
        subtitles = try container.decodeIfPresent([Overlay].self, forKey: .subtitles) ?? []
        subtitleStyle = try container.decodeIfPresent(SubtitleStyle.self, forKey: .subtitleStyle) ?? .default
        captions = try container.decodeIfPresent(Captions.self, forKey: .captions)
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        mediaItems = try container.decodeIfPresent([MediaItem].self, forKey: .mediaItems) ?? []
    }

    public init(
        projectId: ProjectId,
        name: String,
        sources: Sources? = nil,
        takes: [Take] = [],
        timeline: Timeline,
        canvas: Canvas,
        overlays: [Overlay] = [],
        subtitles: [Overlay] = [],
        subtitleStyle: SubtitleStyle = .default,
        chapters: [Chapter] = [],
        captions: Captions? = nil,
        tags: [String] = [],
        schemaVersion: Int = 2,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mediaItems: [MediaItem] = []
    ) {
        self.projectId = projectId
        self.name = name
        self.sources = sources
        self.takes = takes
        self.timeline = timeline
        self.canvas = canvas
        self.overlays = overlays
        self.subtitles = subtitles
        self.subtitleStyle = subtitleStyle
        self.chapters = chapters
        self.captions = captions
        self.tags = tags
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mediaItems = mediaItems
    }

    /// Copy of this project under a different id — used by duplicate and
    /// bundle import, which must not collide with the original.
    public func withNewIdentity(
        projectId newId: ProjectId,
        name newName: String? = nil,
        resetCreatedAt: Bool = false
    ) -> Project {
        Project(
            projectId: newId,
            name: newName ?? name,
            sources: sources,
            takes: takes,
            timeline: timeline,
            canvas: canvas,
            overlays: overlays,
            subtitles: subtitles,
            subtitleStyle: subtitleStyle,
            chapters: chapters,
            captions: captions,
            tags: tags,
            schemaVersion: schemaVersion,
            createdAt: resetCreatedAt ? Date() : createdAt,
            updatedAt: Date(),
            mediaItems: mediaItems
        )
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
