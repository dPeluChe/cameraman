//
//  ZoomSectionControllerTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for ZoomSectionController (Épica I, Task 4)
final class ZoomSectionControllerTests: XCTestCase {

    var controller: ZoomSectionController!
    var mockProject: Project!

    override func setUp() async throws {
        try await super.setUp()
        controller = ZoomSectionController()

        // Create a mock project with multiple segments
        mockProject = Project(
            schemaVersion: 1,
            projectId: ProjectId(),
            name: "Test Project",
            tags: ["test"],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                ),
                camera: nil,
                audio: nil,
                telemetry: nil
            ),
            timeline: Project.Timeline(
                duration: 30.0,
                segments: [
                    Project.Timeline.Segment(
                        id: "segment-1",
                        sourceIn: 0.0,
                        sourceOut: 10.0,
                        timelineIn: 0.0,
                        speed: 1.0,
                        zoom: nil
                    ),
                    Project.Timeline.Segment(
                        id: "segment-2",
                        sourceIn: 10.0,
                        sourceOut: 20.0,
                        timelineIn: 10.0,
                        speed: 1.0,
                        zoom: nil
                    ),
                    Project.Timeline.Segment(
                        id: "segment-3",
                        sourceIn: 20.0,
                        sourceOut: 30.0,
                        timelineIn: 20.0,
                        speed: 1.0,
                        zoom: nil
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                layout: Project.Canvas.Layout(type: "pip", camera: nil)
            ),
            overlays: [],
            captions: nil
        )
    }

    override func tearDown() async throws {
        controller = nil
        mockProject = nil
        try await super.tearDown()
    }

    // MARK: - Project Loading

    func testLoadProject() async throws {
        // Act
        await controller.loadProject(mockProject)

        // Assert
        let updatedProject = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNil(updatedProject, "Segment should have no zoom configuration initially")
    }

    func testUnloadProject() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        await controller.unloadProject()

        // Assert
        do {
            _ = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
            XCTFail("Should throw projectNotLoaded error")
        } catch ZoomSectionController.ZoomSectionError.projectNotLoaded {
            // Expected
        }
    }

    // MARK: - Set Zoom Configuration

    func testSetZoomConfiguration() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let config = Project.Timeline.ZoomConfiguration(
            enabled: true,
            minZoomLevel: 1.0,
            maxZoomLevel: 3.0,
            intensity: nil
        )

        // Act
        let updatedProject = try await controller.setZoomConfiguration(
            forSegmentId: "segment-1",
            configuration: config
        )

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNotNil(retrievedConfig)
        XCTAssertEqual(retrievedConfig?.enabled, true)
        XCTAssertEqual(retrievedConfig?.minZoomLevel, 1.0)
        XCTAssertEqual(retrievedConfig?.maxZoomLevel, 3.0)
        XCTAssertEqual(updatedProject.timeline.segments.first?.zoom?.maxZoomLevel, 3.0)
    }

    func testSetZoomConfigurationForNonExistentSegment() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let config = Project.Timeline.ZoomConfiguration(enabled: true)

        // Act & Assert
        do {
            _ = try await controller.setZoomConfiguration(
                forSegmentId: "non-existent",
                configuration: config
            )
            XCTFail("Should throw segmentNotFound error")
        } catch ZoomSectionController.ZoomSectionError.segmentNotFound {
            // Expected
        }
    }

    func testSetZoomConfigurationWithoutProjectLoaded() async throws {
        // Arrange
        let config = Project.Timeline.ZoomConfiguration(enabled: true)

        // Act & Assert
        do {
            _ = try await controller.setZoomConfiguration(
                forSegmentId: "segment-1",
                configuration: config
            )
            XCTFail("Should throw projectNotLoaded error")
        } catch ZoomSectionController.ZoomSectionError.projectNotLoaded {
            // Expected
        }
    }

    // MARK: - Set Zoom Intensity

    func testSetZoomIntensitySubtle() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        let updatedProject = try await controller.setZoomIntensity(
            forSegmentId: "segment-1",
            intensity: .subtle
        )

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNotNil(retrievedConfig)
        XCTAssertEqual(retrievedConfig?.intensity, .subtle)
        XCTAssertEqual(updatedProject.timeline.segments.first(where: { $0.id == "segment-1" })?.zoom?.intensity, .subtle)
    }

    func testSetZoomIntensityNormal() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        _ = try await controller.setZoomIntensity(
            forSegmentId: "segment-2",
            intensity: .normal
        )

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-2")
        XCTAssertEqual(retrievedConfig?.intensity, .normal)
    }

    func testSetZoomIntensityAggressive() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        _ = try await controller.setZoomIntensity(
            forSegmentId: "segment-3",
            intensity: .aggressive
        )

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-3")
        XCTAssertEqual(retrievedConfig?.intensity, .aggressive)
    }

    func testSetZoomIntensityDisabled() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        _ = try await controller.setZoomIntensity(
            forSegmentId: "segment-1",
            intensity: .disabled
        )

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertEqual(retrievedConfig?.intensity, .disabled)
        XCTAssertEqual(retrievedConfig?.enabled, false)
    }

    // MARK: - Enable/Disable Zoom

    func testEnableZoom() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // First disable zoom
        _ = try await controller.setZoomIntensity(
            forSegmentId: "segment-1",
            intensity: .disabled
        )

        // Act
        let updatedProject = try await controller.enableZoom(forSegmentId: "segment-1")

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNotNil(retrievedConfig)
        XCTAssertEqual(retrievedConfig?.enabled, true)
        XCTAssertEqual(updatedProject.timeline.segments.first?.zoom?.enabled, true)
    }

    func testDisableZoom() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        let updatedProject = try await controller.disableZoom(forSegmentId: "segment-1")

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNotNil(retrievedConfig)
        XCTAssertEqual(retrievedConfig?.enabled, false)
        XCTAssertEqual(updatedProject.timeline.segments.first?.zoom?.enabled, false)
    }

    func testDisableZoomForAllSegments() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        let updatedProject = try await controller.disableZoomForAllSegments()

        // Assert
        for segment in updatedProject.timeline.segments {
            let config = try await controller.getZoomConfiguration(forSegmentId: segment.id)
            XCTAssertNotNil(config)
            XCTAssertEqual(config?.enabled, false, "Segment \(segment.id) should have zoom disabled")
        }
    }

    func testEnableZoomForAllSegments() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // First disable all zoom
        _ = try await controller.disableZoomForAllSegments()

        // Act
        let updatedProject = try await controller.enableZoomForAllSegments()

        // Assert
        // Segments with explicit disabled configuration should have it removed (nil)
        // which means they'll use the default (enabled)
        for segment in updatedProject.timeline.segments {
            let config = try await controller.getZoomConfiguration(forSegmentId: segment.id)
            if segment.id == "segment-1" || segment.id == "segment-2" || segment.id == "segment-3" {
                XCTAssertNil(config, "Segment \(segment.id) should have no explicit configuration (uses default)")
            }
        }
    }

    // MARK: - Remove Zoom Configuration

    func testRemoveZoomConfiguration() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let config = Project.Timeline.ZoomConfiguration(enabled: true)
        _ = try await controller.setZoomConfiguration(forSegmentId: "segment-1", configuration: config)

        // Act
        let updatedProject = try await controller.removeZoomConfiguration(forSegmentId: "segment-1")

        // Assert
        let retrievedConfig = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        XCTAssertNil(retrievedConfig, "Configuration should be removed")
        XCTAssertNil(updatedProject.timeline.segments.first(where: { $0.id == "segment-1" })?.zoom)
    }

    // MARK: - Get Segments with Zoom Enabled/Disabled

    func testGetSegmentsWithZoomEnabled() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.disableZoom(forSegmentId: "segment-2")

        // Act
        let enabledSegments = try await controller.getSegmentsWithZoomEnabled()

        // Assert
        XCTAssertTrue(enabledSegments.contains("segment-1"))
        XCTAssertTrue(enabledSegments.contains("segment-3"))
        XCTAssertFalse(enabledSegments.contains("segment-2"))
    }

    func testGetSegmentsWithZoomDisabled() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.disableZoom(forSegmentId: "segment-1")
        _ = try await controller.disableZoom(forSegmentId: "segment-3")

        // Act
        let disabledSegments = try await controller.getSegmentsWithZoomDisabled()

        // Assert
        XCTAssertTrue(disabledSegments.contains("segment-1"))
        XCTAssertTrue(disabledSegments.contains("segment-3"))
        XCTAssertFalse(disabledSegments.contains("segment-2"))
    }

    // MARK: - Get All Zoom Configurations

    func testGetAllZoomConfigurations() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-1", intensity: .subtle)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-2", intensity: .aggressive)

        // Act
        let allConfigs = try await controller.getAllZoomConfigurations()

        // Assert
        XCTAssertEqual(allConfigs.count, 2)
        XCTAssertNotNil(allConfigs["segment-1"])
        XCTAssertNotNil(allConfigs["segment-2"])
        XCTAssertEqual(allConfigs["segment-1"]?.intensity, .subtle)
        XCTAssertEqual(allConfigs["segment-2"]?.intensity, .aggressive)
        XCTAssertNil(allConfigs["segment-3"])
    }

    // MARK: - Get Zoom Summary

    func testGetZoomSummary() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-1", intensity: .subtle)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-2", intensity: .aggressive)
        _ = try await controller.disableZoom(forSegmentId: "segment-3")

        // Act
        let summary = try await controller.getZoomSummary()

        // Assert
        XCTAssertEqual(summary.totalSegments, 3)
        XCTAssertEqual(summary.zoomEnabledSegments, 2)
        XCTAssertEqual(summary.zoomDisabledSegments, 1)
        XCTAssertEqual(summary.customConfiguredSegments, 3)
        XCTAssertEqual(summary.segmentsByIntensity[.subtle], 1)
        XCTAssertEqual(summary.segmentsByIntensity[.aggressive], 1)
        XCTAssertEqual(summary.segmentsByIntensity[.disabled], 1)
        XCTAssertLessThan(summary.zoomEnabledPercentage, 100)
        XCTAssertGreaterThan(summary.zoomEnabledPercentage, 0)
    }

    func testGetZoomSummaryWithNoConfigurations() async throws {
        // Arrange
        await controller.loadProject(mockProject)

        // Act
        let summary = try await controller.getZoomSummary()

        // Assert
        XCTAssertEqual(summary.totalSegments, 3)
        XCTAssertEqual(summary.zoomEnabledSegments, 3) // All segments default to enabled
        XCTAssertEqual(summary.zoomDisabledSegments, 0)
        XCTAssertEqual(summary.customConfiguredSegments, 0)
        XCTAssertEqual(summary.zoomEnabledPercentage, 100.0)
    }

    // MARK: - Set Multiple Segment Configurations

    func testSetZoomConfigurationForMultipleSegments() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let configs = [
            "segment-1": Project.Timeline.ZoomConfiguration(intensity: .subtle),
            "segment-2": Project.Timeline.ZoomConfiguration(intensity: .aggressive)
        ]

        // Act
        let updatedProject = try await controller.setZoomConfigurationForMultipleSegments(configs)

        // Assert
        let config1 = try await controller.getZoomConfiguration(forSegmentId: "segment-1")
        let config2 = try await controller.getZoomConfiguration(forSegmentId: "segment-2")
        XCTAssertEqual(config1?.intensity, .subtle)
        XCTAssertEqual(config2?.intensity, .aggressive)
        XCTAssertNil(updatedProject.timeline.segments.first(where: { $0.id == "segment-3" })?.zoom)
    }

    func testSetZoomConfigurationForMultipleSegmentsWithInvalidId() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let configs = [
            "segment-1": Project.Timeline.ZoomConfiguration(intensity: .subtle),
            "invalid-id": Project.Timeline.ZoomConfiguration(intensity: .aggressive)
        ]

        // Act & Assert
        do {
            _ = try await controller.setZoomConfigurationForMultipleSegments(configs)
            XCTFail("Should throw segmentNotFound error")
        } catch ZoomSectionController.ZoomSectionError.segmentNotFound(let message) {
            XCTAssertTrue(message.contains("invalid-id"))
        }
    }

    // MARK: - Get Effective Zoom Configuration

    func testGetEffectiveZoomConfigurationWithExplicitConfig() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-1", intensity: .subtle)
        let baseConfig = ZoomPlanGenerator.Configuration.default()

        // Act
        let effectiveConfig = try await controller.getEffectiveZoomConfiguration(
            forSegmentId: "segment-1",
            baseConfiguration: baseConfig
        )

        // Assert
        XCTAssertNotNil(effectiveConfig)
        XCTAssertTrue(effectiveConfig.zoomEnabled)
        XCTAssertLessThan(effectiveConfig.maxZoomLevel, 2.0) // Subtle has lower max zoom
    }

    func testGetEffectiveZoomConfigurationWithDisabledConfig() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.disableZoom(forSegmentId: "segment-1")
        let baseConfig = ZoomPlanGenerator.Configuration.default()

        // Act
        let effectiveConfig = try await controller.getEffectiveZoomConfiguration(
            forSegmentId: "segment-1",
            baseConfiguration: baseConfig
        )

        // Assert
        XCTAssertFalse(effectiveConfig.zoomEnabled)
    }

    func testGetEffectiveZoomConfigurationWithNoExplicitConfig() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        let baseConfig = ZoomPlanGenerator.Configuration.default()

        // Act
        let effectiveConfig = try await controller.getEffectiveZoomConfiguration(
            forSegmentId: "segment-1",
            baseConfiguration: baseConfig
        )

        // Assert
        // Should return base configuration
        XCTAssertTrue(effectiveConfig.zoomEnabled)
        XCTAssertEqual(effectiveConfig.maxZoomLevel, baseConfig.maxZoomLevel)
    }

    // MARK: - Default Configuration

    func testSetDefaultConfiguration() async throws {
        // Arrange
        let customConfig = ZoomPlanGenerator.Configuration.subtle()

        // Act
        await controller.setDefaultConfiguration(customConfig)

        // Assert
        let retrievedConfig = await controller.getDefaultConfiguration()
        XCTAssertEqual(retrievedConfig.maxZoomLevel, customConfig.maxZoomLevel)
        XCTAssertLessThan(retrievedConfig.maxZoomLevel, 2.0)
    }

    // MARK: - ZoomConfiguration Presets

    func testZoomConfigurationPresets() async throws {
        // Test all preset configurations
        XCTAssertEqual(Project.Timeline.ZoomConfiguration.disabled.enabled, false)
        XCTAssertEqual(Project.Timeline.ZoomConfiguration.subtle.intensity, .subtle)
        XCTAssertEqual(Project.Timeline.ZoomConfiguration.normal.intensity, .normal)
        XCTAssertEqual(Project.Timeline.ZoomConfiguration.aggressive.intensity, .aggressive)
    }

    func testZoomIntensityToConfiguration() async throws {
        // Test intensity preset conversion to ZoomPlanGenerator.Configuration
        let baseConfig = ZoomPlanGenerator.Configuration.default()

        let subtleConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.subtle.toConfiguration(base: baseConfig)
        XCTAssertTrue(subtleConfig.zoomEnabled)
        XCTAssertLessThan(subtleConfig.maxZoomLevel, 2.0)

        let aggressiveConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.aggressive.toConfiguration(base: baseConfig)
        XCTAssertTrue(aggressiveConfig.zoomEnabled)
        XCTAssertGreaterThan(aggressiveConfig.maxZoomLevel, 3.0)

        let disabledConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.disabled.toConfiguration(base: baseConfig)
        XCTAssertFalse(disabledConfig.zoomEnabled)
    }

    // MARK: - Performance Tests

    func testZoomConfigurationPerformance() async throws {
        // Measure performance of setting/getting configurations
        await controller.loadProject(mockProject)

        measure {
            Task {
                for i in 0..<100 {
                    let segmentId = "segment-\(i % 3 + 1)"
                    _ = try? await controller.setZoomIntensity(
                        forSegmentId: segmentId,
                        intensity: .subtle
                    )
                }
            }
        }
    }

    func testZoomSummaryPerformance() async throws {
        // Arrange
        await controller.loadProject(mockProject)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-1", intensity: .subtle)
        _ = try await controller.setZoomIntensity(forSegmentId: "segment-2", intensity: .aggressive)

        measure {
            Task {
                _ = try? await controller.getZoomSummary()
            }
        }
    }
}
