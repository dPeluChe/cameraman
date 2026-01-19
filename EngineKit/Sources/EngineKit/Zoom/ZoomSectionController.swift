//
//  ZoomSectionController.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// ZoomSectionController manages per-section zoom settings for timeline segments
/// Provides APIs to get/set zoom configuration for specific sections (Épica I, Task 4)
public actor ZoomSectionController {
    // MARK: - Types

    /// Errors that can occur during zoom section management
    public enum ZoomSectionError: LocalizedError {
        case segmentNotFound(String)
        case invalidConfiguration(String)
        case projectNotLoaded

        public var errorDescription: String? {
            switch self {
            case .segmentNotFound(let id):
                return "Segment not found: \(id)"
            case .invalidConfiguration(let message):
                return "Invalid zoom configuration: \(message)"
            case .projectNotLoaded:
                return "No project loaded"
            }
        }
    }

    /// Summary of zoom configuration across all segments
    public struct ZoomSummary: Codable, Equatable {
        /// Total number of segments
        public let totalSegments: Int
        /// Number of segments with zoom enabled
        public let zoomEnabledSegments: Int
        /// Number of segments with zoom disabled
        public let zoomDisabledSegments: Int
        /// Number of segments with custom configuration
        public let customConfiguredSegments: Int
        /// Segments grouped by intensity
        public let segmentsByIntensity: [Project.Timeline.Segment.ZoomConfiguration.ZoomIntensity: Int]
        /// Percentage of timeline with zoom enabled
        public let zoomEnabledPercentage: Double

        public init(
            totalSegments: Int,
            zoomEnabledSegments: Int,
            zoomDisabledSegments: Int,
            customConfiguredSegments: Int,
            segmentsByIntensity: [Project.Timeline.Segment.ZoomConfiguration.ZoomIntensity: Int],
            zoomEnabledPercentage: Double
        ) {
            self.totalSegments = totalSegments
            self.zoomEnabledSegments = zoomEnabledSegments
            self.zoomDisabledSegments = zoomDisabledSegments
            self.customConfiguredSegments = customConfiguredSegments
            self.segmentsByIntensity = segmentsByIntensity
            self.zoomEnabledPercentage = zoomEnabledPercentage
        }
    }

    // MARK: - Properties

    /// Currently loaded project
    private var project: Project?

    /// Default zoom configuration for segments without explicit configuration
    private var defaultConfiguration: ZoomPlanGenerator.Configuration

    // MARK: - Initialization

    /// Initialize the controller
    /// - Parameter defaultConfiguration: Default zoom configuration for segments
    public init(defaultConfiguration: ZoomPlanGenerator.Configuration = .default()) {
        self.defaultConfiguration = defaultConfiguration
    }

    // MARK: - Public Methods

    /// Load a project for zoom section management
    /// - Parameter project: Project to manage
    public func loadProject(_ project: Project) {
        self.project = project
    }

    /// Unload the current project
    public func unloadProject() {
        self.project = nil
    }

    /// Set zoom configuration for a specific segment
    /// - Parameters:
    ///   - segmentId: ID of the segment to configure
    ///   - configuration: Zoom configuration to apply
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if segment not found or configuration is invalid
    public func setZoomConfiguration(
        forSegmentId segmentId: String,
        configuration: Project.Timeline.Segment.ZoomConfiguration
    ) throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        // Update the segment's zoom configuration
        project.timeline.segments[index].zoom = configuration
        project.updatedAt = Date()

        self.project = project
        return project
    }

    /// Set zoom intensity for a specific segment
    /// - Parameters:
    ///   - segmentId: ID of the segment to configure
    ///   - intensity: Zoom intensity preset
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if segment not found
    public func setZoomIntensity(
        forSegmentId segmentId: String,
        intensity: Project.Timeline.Segment.ZoomConfiguration.ZoomIntensity
    ) throws -> Project {
        let configuration = Project.Timeline.Segment.ZoomConfiguration(intensity: intensity)
        return try setZoomConfiguration(forSegmentId: segmentId, configuration: configuration)
    }

    /// Enable zoom for a specific segment
    /// - Parameter segmentId: ID of the segment to enable zoom for
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if segment not found
    public func enableZoom(forSegmentId segmentId: String) throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        // Get existing configuration or create default
        let existingConfig = project.timeline.segments[index].zoom
        let newConfig = Project.Timeline.Segment.ZoomConfiguration(
            enabled: true,
            minZoomLevel: existingConfig?.minZoomLevel ?? 1.0,
            maxZoomLevel: existingConfig?.maxZoomLevel ?? 2.5,
            intensity: existingConfig?.intensity ?? .normal
        )

        project.timeline.segments[index].zoom = newConfig
        project.updatedAt = Date()

        self.project = project
        return project
    }

    /// Disable zoom for a specific segment
    /// - Parameter segmentId: ID of the segment to disable zoom for
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if segment not found
    public func disableZoom(forSegmentId segmentId: String) throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        // Set zoom to disabled configuration
        project.timeline.segments[index].zoom = .disabled
        project.updatedAt = Date()

        self.project = project
        return project
    }

    /// Remove zoom configuration for a specific segment (reverts to defaults)
    /// - Parameter segmentId: ID of the segment to remove configuration from
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if segment not found
    public func removeZoomConfiguration(forSegmentId segmentId: String) throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        // Remove zoom configuration (will use defaults)
        project.timeline.segments[index].zoom = nil
        project.updatedAt = Date()

        self.project = project
        return project
    }

    /// Get zoom configuration for a specific segment
    /// - Parameter segmentId: ID of the segment to query
    /// - Returns: Zoom configuration if set, nil otherwise (uses defaults)
    /// - Throws: ZoomSectionError if segment not found
    public func getZoomConfiguration(forSegmentId segmentId: String) throws -> Project.Timeline.Segment.ZoomConfiguration? {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let segment = project.timeline.segments.first(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        return segment.zoom
    }

    /// Get all segments with zoom enabled
    /// - Returns: Array of segment IDs with zoom enabled
    /// - Throws: ZoomSectionError if project not loaded
    public func getSegmentsWithZoomEnabled() throws -> [String] {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        return project.timeline.segments
            .filter { $0.zoom?.enabled ?? true } // Default to enabled if not set
            .map { $0.id }
    }

    /// Get all segments with zoom disabled
    /// - Returns: Array of segment IDs with zoom disabled
    /// - Throws: ZoomSectionError if project not loaded
    public func getSegmentsWithZoomDisabled() throws -> [String] {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        return project.timeline.segments
            .filter { segment in
                if let zoom = segment.zoom {
                    return !zoom.enabled
                }
                return false // Default is enabled
            }
            .map { $0.id }
    }

    /// Get zoom configuration for all segments
    /// - Returns: Dictionary mapping segment IDs to their zoom configurations
    /// - Throws: ZoomSectionError if project not loaded
    public func getAllZoomConfigurations() throws -> [String: Project.Timeline.Segment.ZoomConfiguration] {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        var configurations: [String: Project.Timeline.Segment.ZoomConfiguration] = [:]

        for segment in project.timeline.segments {
            if let zoom = segment.zoom {
                configurations[segment.id] = zoom
            }
        }

        return configurations
    }

    /// Get a summary of zoom configuration across all segments
    /// - Returns: ZoomSummary with statistics
    /// - Throws: ZoomSectionError if project not loaded
    public func getZoomSummary() throws -> ZoomSummary {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        let totalSegments = project.timeline.segments.count
        var zoomEnabledSegments = 0
        var zoomDisabledSegments = 0
        var customConfiguredSegments = 0
        var segmentsByIntensity: [Project.Timeline.Segment.ZoomConfiguration.ZoomIntensity: Int] = [:]
        var totalDurationWithZoom: TimeInterval = 0

        for segment in project.timeline.segments {
            if let zoom = segment.zoom {
                customConfiguredSegments += 1

                if zoom.enabled {
                    zoomEnabledSegments += 1
                    totalDurationWithZoom += (segment.timelineOut - segment.timelineIn)
                } else {
                    zoomDisabledSegments += 1
                }

                if let intensity = zoom.intensity {
                    segmentsByIntensity[intensity, default: 0] += 1
                }
            } else {
                // No explicit configuration, defaults to enabled
                zoomEnabledSegments += 1
                totalDurationWithZoom += (segment.timelineOut - segment.timelineIn)
            }
        }

        let zoomEnabledPercentage = project.timeline.duration > 0
            ? (totalDurationWithZoom / project.timeline.duration) * 100
            : 0

        return ZoomSummary(
            totalSegments: totalSegments,
            zoomEnabledSegments: zoomEnabledSegments,
            zoomDisabledSegments: zoomDisabledSegments,
            customConfiguredSegments: customConfiguredSegments,
            segmentsByIntensity: segmentsByIntensity,
            zoomEnabledPercentage: zoomEnabledPercentage
        )
    }

    /// Set zoom configuration for multiple segments at once
    /// - Parameters:
    ///   - configurations: Dictionary mapping segment IDs to zoom configurations
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if any segment not found
    public func setZoomConfigurationForMultipleSegments(
        _ configurations: [String: Project.Timeline.Segment.ZoomConfiguration]
    ) throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        var notFoundIds: [String] = []

        for (segmentId, configuration) in configurations {
            if let index = project.timeline.segments.firstIndex(where: { $0.id == segmentId }) {
                project.timeline.segments[index].zoom = configuration
            } else {
                notFoundIds.append(segmentId)
            }
        }

        if !notFoundIds.isEmpty {
            throw ZoomSectionError.segmentNotFound(notFoundIds.joined(separator: ", "))
        }

        project.updatedAt = Date()
        self.project = project
        return project
    }

    /// Enable zoom for all segments
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if project not loaded
    public func enableZoomForAllSegments() throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        for index in project.timeline.segments.indices {
            // Only update if zoom is explicitly disabled
            if project.timeline.segments[index].zoom?.enabled == false {
                project.timeline.segments[index].zoom = nil // Revert to default (enabled)
            }
        }

        project.updatedAt = Date()
        self.project = project
        return project
    }

    /// Disable zoom for all segments
    /// - Returns: Updated project
    /// - Throws: ZoomSectionError if project not loaded
    public func disableZoomForAllSegments() throws -> Project {
        guard var project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        for index in project.timeline.segments.indices {
            project.timeline.segments[index].zoom = .disabled
        }

        project.updatedAt = Date()
        self.project = project
        return project
    }

    /// Get the zoom configuration to use for a specific segment
    /// This returns either the segment's explicit configuration or a default one
    /// - Parameters:
    ///   - segmentId: ID of the segment
    ///   - baseConfiguration: Base configuration to use as defaults
    /// - Returns: ZoomPlanGenerator.Configuration for this segment
    /// - Throws: ZoomSectionError if segment not found
    public func getEffectiveZoomConfiguration(
        forSegmentId segmentId: String,
        baseConfiguration: ZoomPlanGenerator.Configuration
    ) throws -> ZoomPlanGenerator.Configuration {
        guard let project = project else {
            throw ZoomSectionError.projectNotLoaded
        }

        guard let segment = project.timeline.segments.first(where: { $0.id == segmentId }) else {
            throw ZoomSectionError.segmentNotFound(segmentId)
        }

        // If segment has explicit zoom configuration, use it
        if let zoomConfig = segment.zoom {
            if let intensity = zoomConfig.intensity {
                // Use intensity preset
                return intensity.toConfiguration(base: baseConfiguration)
            } else {
                // Use custom configuration
                return ZoomPlanGenerator.Configuration(
                    minZoomLevel: zoomConfig.minZoomLevel,
                    maxZoomLevel: zoomConfig.maxZoomLevel,
                    defaultZoomLevel: baseConfiguration.defaultZoomLevel,
                    zoomInDuration: baseConfiguration.zoomInDuration,
                    zoomOutDuration: baseConfiguration.zoomOutDuration,
                    holdDuration: baseConfiguration.holdDuration,
                    boundingBoxPadding: baseConfiguration.boundingBoxPadding,
                    easingFunction: baseConfiguration.easingFunction,
                    maxZoomsPerMinute: baseConfiguration.maxZoomsPerMinute,
                    minTimeBetweenZooms: baseConfiguration.minTimeBetweenZooms,
                    zoomEnabled: zoomConfig.enabled
                )
            }
        }

        // No explicit configuration, use base
        return baseConfiguration
    }

    /// Set the default zoom configuration for segments without explicit configuration
    /// - Parameter configuration: Default configuration to use
    public func setDefaultConfiguration(_ configuration: ZoomPlanGenerator.Configuration) {
        self.defaultConfiguration = configuration
    }

    /// Get the default zoom configuration
    /// - Returns: Current default configuration
    public func getDefaultConfiguration() -> ZoomPlanGenerator.Configuration {
        return defaultConfiguration
    }
}
