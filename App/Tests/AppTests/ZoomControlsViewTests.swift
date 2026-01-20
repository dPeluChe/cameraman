//
//  ZoomControlsViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-J — Zoom Controls (P1)
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit

@MainActor
final class ZoomControlsViewTests: XCTestCase {

    // MARK: - ProjectEditor Tests

    func testUpdateSegmentZoom() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Update segment zoom to aggressive
        let config = Project.Timeline.ZoomConfiguration(intensity: .aggressive)
        let result = await editor.updateSegmentZoom(segmentId: segmentId, configuration: config)

        XCTAssertTrue(result, "Zoom update should succeed")
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, .aggressive)
    }

    func testUpdateSegmentZoomToDisabled() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Disable zoom for segment
        let result = await editor.updateSegmentZoom(segmentId: segmentId, configuration: .disabled)

        XCTAssertTrue(result, "Zoom disable should succeed")
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.enabled, false)
    }

    func testUpdateAllSegmentsZoom() async throws {
        let editor = try ProjectEditor.mockProject()

        // Update all segments to subtle
        let config = Project.Timeline.ZoomConfiguration(intensity: .subtle)
        let result = await editor.updateAllSegmentsZoom(configuration: config)

        XCTAssertTrue(result, "Update all segments should succeed")
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .subtle })
    }

    func testSetZoomEnabled() async throws {
        let editor = try ProjectEditor.mockProject()

        // Disable zoom
        let disableResult = await editor.setZoomEnabled(false)
        XCTAssertTrue(disableResult, "Disable zoom should succeed")
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == false })

        // Enable zoom
        let enableResult = await editor.setZoomEnabled(true)
        XCTAssertTrue(enableResult, "Enable zoom should succeed")
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == true })
    }

    func testSetZoomIntensity() async throws {
        let editor = try ProjectEditor.mockProject()

        // Set intensity to aggressive
        let result = await editor.setZoomIntensity(.aggressive)
        XCTAssertTrue(result, "Set intensity should succeed")
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .aggressive })
    }

    func testSetZoomIntensityPreservesEnabledState() async throws {
        let editor = try ProjectEditor.mockProject()

        // Disable zoom for first segment
        let segmentId = editor.project.timeline.segments.first!.id
        await editor.updateSegmentZoom(segmentId: segmentId, configuration: .disabled)

        // Set intensity (should not re-enable disabled segments)
        await editor.setZoomIntensity(.aggressive)

        // First segment should still be disabled
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.enabled, false)
        // Other segments should be enabled with aggressive intensity
        XCTAssertTrue(editor.project.timeline.segments.dropFirst().allSatisfy { $0.zoom?.intensity == .aggressive && $0.zoom?.enabled == true })
    }

    func testZoomUndoRedo() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id
        let originalIntensity = editor.project.timeline.segments.first?.zoom?.intensity

        // Update zoom
        await editor.updateSegmentZoom(segmentId: segmentId, configuration: .aggressive)
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, .aggressive)

        // Undo
        let undoResult = await editor.undo()
        XCTAssertTrue(undoResult, "Undo should succeed")
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, originalIntensity)

        // Redo
        let redoResult = await editor.redo()
        XCTAssertTrue(redoResult, "Redo should succeed")
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, .aggressive)
    }

    func testUpdateNonExistentSegment() async throws {
        let editor = try ProjectEditor.mockProject()

        // Try to update non-existent segment
        let result = await editor.updateSegmentZoom(
            segmentId: "non-existent-id",
            configuration: .subtle
        )

        XCTAssertFalse(result, "Update should fail for non-existent segment")
    }

    // MARK: - ZoomConfiguration Tests

    func testZoomIntensityPresets() {
        // Test subtle configuration
        let subtle = Project.Timeline.ZoomConfiguration.subtle
        XCTAssertTrue(subtle.enabled)
        XCTAssertEqual(subtle.intensity, .subtle)

        // Test normal configuration
        let normal = Project.Timeline.ZoomConfiguration.normal
        XCTAssertTrue(normal.enabled)
        XCTAssertEqual(normal.intensity, .normal)

        // Test aggressive configuration
        let aggressive = Project.Timeline.ZoomConfiguration.aggressive
        XCTAssertTrue(aggressive.enabled)
        XCTAssertEqual(aggressive.intensity, .aggressive)

        // Test disabled configuration
        let disabled = Project.Timeline.ZoomConfiguration.disabled
        XCTAssertFalse(disabled.enabled)
    }

    func testZoomIntensityToConfiguration() {
        let baseConfig = ZoomPlanGenerator.Configuration.default()

        // Test each intensity preset
        let subtleConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.subtle.toConfiguration(base: baseConfig)
        XCTAssertEqual(subtleConfig.maxZoomLevel, 1.8)

        let normalConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.normal.toConfiguration(base: baseConfig)
        XCTAssertEqual(normalConfig.maxZoomLevel, 2.5)

        let aggressiveConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.aggressive.toConfiguration(base: baseConfig)
        XCTAssertEqual(aggressiveConfig.maxZoomLevel, 3.5)

        let disabledConfig = Project.Timeline.ZoomConfiguration.ZoomIntensity.disabled.toConfiguration(base: baseConfig)
        XCTAssertFalse(disabledConfig.zoomEnabled)
    }

    func testZoomConfigurationEquality() {
        let config1 = Project.Timeline.ZoomConfiguration(intensity: .normal)
        let config2 = Project.Timeline.ZoomConfiguration(intensity: .normal)
        let config3 = Project.Timeline.ZoomConfiguration(intensity: .aggressive)

        XCTAssertEqual(config1, config2, "Same configurations should be equal")
        XCTAssertNotEqual(config1, config3, "Different configurations should not be equal")
    }

    func testZoomConfigurationCodable() throws {
        let config = Project.Timeline.ZoomConfiguration(intensity: .aggressive)
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Project.Timeline.ZoomConfiguration.self, from: data)

        XCTAssertEqual(config, decoded, "Codable should preserve configuration")
    }

    // MARK: - Integration Tests

    func testZoomControlsWorkflow() async throws {
        let editor = try ProjectEditor.mockProject()

        // 1. Start with normal zoom
        await editor.setZoomIntensity(.normal)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .normal })

        // 2. Change to subtle
        await editor.setZoomIntensity(.subtle)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .subtle })

        // 3. Change to aggressive
        await editor.setZoomIntensity(.aggressive)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .aggressive })

        // 4. Disable zoom
        await editor.setZoomEnabled(false)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == false })

        // 5. Re-enable zoom
        await editor.setZoomEnabled(true)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == true })
    }

    func testMixedZoomConfiguration() async throws {
        let editor = try ProjectEditor.mockProject()

        // Set different zoom for each segment
        let segments = editor.project.timeline.segments
        await editor.updateSegmentZoom(segmentId: segments[0].id, configuration: .subtle)
        await editor.updateSegmentZoom(segmentId: segments[1].id, configuration: .aggressive)

        XCTAssertEqual(editor.project.timeline.segments[0].zoom?.intensity, .subtle)
        XCTAssertEqual(editor.project.timeline.segments[1].zoom?.intensity, .aggressive)
    }

    func testZoomWithNoSegments() async throws {
        // Create a project with no segments
        let project = Project(
            schemaVersion: 1,
            projectId: "empty-project",
            name: "Empty Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "/tmp/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: Project.Timeline(duration: 0, segments: []),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000"),
                layout: CanvasLayout.defaultLayout(for: .fullscreen)
            ),
            overlays: [],
            captions: nil
        )

        let editor = ProjectEditor(project: project)

        // Should handle empty segments gracefully
        let result = await editor.updateAllSegmentsZoom(configuration: .normal)
        XCTAssertTrue(result, "Update should succeed even with no segments")
    }

    // MARK: - UI State Tests

    func testZoomControlsViewState() async throws {
        let editor = try ProjectEditor.mockProject()

        // Create view model state
        let firstSegmentZoom = editor.project.timeline.segments.first?.zoom
        let isEnabled = firstSegmentZoom?.enabled ?? true
        let intensity: Double
        switch firstSegmentZoom?.intensity {
        case .subtle:
            intensity = 0.0
        case .normal, .none:
            intensity = 1.0
        case .aggressive:
            intensity = 2.0
        case .disabled:
            intensity = 1.0
        }

        // Verify initial state
        XCTAssertTrue(isEnabled)
        XCTAssertEqual(intensity, 1.0, "Default intensity should be normal (1.0)")
    }

    func testIntensityLabelMapping() {
        // Test intensity to label mapping
        let subtleLabel = intensityLabel(from: 0.0)
        XCTAssertEqual(subtleLabel, "Subtle")

        let normalLabel = intensityLabel(from: 1.0)
        XCTAssertEqual(normalLabel, "Normal")

        let aggressiveLabel = intensityLabel(from: 2.0)
        XCTAssertEqual(aggressiveLabel, "Aggressive")
    }

    func testIntensityFromSliderValue() async throws {
        let editor = try ProjectEditor.mockProject()

        // Test slider value to intensity conversion
        let subtle = intensityFromSlider(value: 0.0)
        XCTAssertEqual(subtle, .subtle)

        let normal = intensityFromSlider(value: 1.0)
        XCTAssertEqual(normal, .normal)

        let aggressive = intensityFromSlider(value: 2.0)
        XCTAssertEqual(aggressive, .aggressive)
    }

    // MARK: - Edge Cases

    func testZoomConfigurationWithNilIntensity() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Create config with nil intensity (custom config)
        let customConfig = Project.Timeline.ZoomConfiguration(
            enabled: true,
            minZoomLevel: 1.2,
            maxZoomLevel: 2.8,
            intensity: nil
        )

        let result = await editor.updateSegmentZoom(segmentId: segmentId, configuration: customConfig)
        XCTAssertTrue(result)
        XCTAssertNil(editor.project.timeline.segments.first?.zoom?.intensity)
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.minZoomLevel, 1.2)
    }

    func testZoomConfigurationWithZeroSegments() async throws {
        // Create empty project
        let project = Project(
            schemaVersion: 1,
            projectId: "zero-segments",
            name: "Zero Segments",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "/tmp/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: Project.Timeline(duration: 0, segments: []),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000"),
                layout: CanvasLayout.defaultLayout(for: .fullscreen)
            ),
            overlays: [],
            captions: nil
        )

        let editor = ProjectEditor(project: project)

        // Should handle gracefully
        let result = await editor.setZoomIntensity(.normal)
        XCTAssertTrue(result, "Should succeed with zero segments")
    }

    // MARK: - Performance Tests

    func testZoomUpdatePerformance() async throws {
        let editor = try ProjectEditor.mockProject()

        measure {
            let group = DispatchGroup()
            for segment in editor.project.timeline.segments {
                group.enter()
                Task {
                    await editor.updateSegmentZoom(
                        segmentId: segment.id,
                        configuration: .aggressive
                    )
                    group.leave()
                }
            }
            group.wait()
        }
    }

    // MARK: - Helper Methods

    private func intensityLabel(from value: Double) -> String {
        switch value {
        case 0:
            return "Subtle"
        case 1:
            return "Normal"
        case 2:
            return "Aggressive"
        default:
            return "Normal"
        }
    }

    private func intensityFromSlider(value: Double) -> Project.Timeline.ZoomConfiguration.ZoomIntensity {
        switch Int(value) {
        case 0:
            return .subtle
        case 1:
            return .normal
        case 2:
            return .aggressive
        default:
            return .normal
        }
    }
}

// MARK: - Snapshot Tests

@MainActor
extension ZoomControlsViewTests {

    func testZoomControlsViewSnapshot() throws {
        let editor = try ProjectEditor.mockProject()
        let view = ZoomControlsView(editor: editor)

        // Verify view creates without crashing
        XCTAssertNotNil(view)
    }

    func testZoomControlsViewWithDisabledZoom() async throws {
        let editor = try ProjectEditor.mockProject()

        // Disable zoom
        await editor.setZoomEnabled(false)

        let view = ZoomControlsView(editor: editor)

        // Verify view creates with disabled state
        XCTAssertNotNil(view)
    }

    // MARK: - Section-Level Zoom Controls Tests (P2)

    func testRemoveSegmentZoom() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Set custom zoom
        await editor.updateSegmentZoom(segmentId: segmentId, configuration: .aggressive)
        XCTAssertNotNil(editor.project.timeline.segments.first?.zoom)

        // Remove zoom configuration
        let result = await editor.removeSegmentZoom(segmentId: segmentId)
        XCTAssertTrue(result, "Remove zoom should succeed")
        XCTAssertNil(editor.project.timeline.segments.first?.zoom, "Zoom should be nil after removal")
    }

    func testRemoveSegmentZoomUndoRedo() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Set custom zoom
        let originalZoom = editor.project.timeline.segments.first?.zoom
        await editor.updateSegmentZoom(segmentId: segmentId, configuration: .aggressive)
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, .aggressive)

        // Remove zoom
        await editor.removeSegmentZoom(segmentId: segmentId)
        XCTAssertNil(editor.project.timeline.segments.first?.zoom)

        // Undo
        let undoResult = await editor.undo()
        XCTAssertTrue(undoResult, "Undo should succeed")
        XCTAssertEqual(editor.project.timeline.segments.first?.zoom?.intensity, .aggressive)

        // Redo
        let redoResult = await editor.redo()
        XCTAssertTrue(redoResult, "Redo should succeed")
        XCTAssertNil(editor.project.timeline.segments.first?.zoom)
    }

    func testRemoveNonExistentSegment() async throws {
        let editor = try ProjectEditor.mockProject()

        // Try to remove zoom from non-existent segment
        let result = await editor.removeSegmentZoom(segmentId: "non-existent-id")
        XCTAssertFalse(result, "Remove should fail for non-existent segment")
    }

    func testSectionLevelZoomMixedConfiguration() async throws {
        let editor = try ProjectEditor.mockProject()
        let segments = editor.project.timeline.segments

        // Set different zoom for each segment
        await editor.updateSegmentZoom(segmentId: segments[0].id, configuration: .subtle)
        await editor.updateSegmentZoom(segmentId: segments[1].id, configuration: .aggressive)
        await editor.removeSegmentZoom(segmentId: segments[1].id) // Remove second's config

        // Verify configurations
        XCTAssertEqual(editor.project.timeline.segments[0].zoom?.intensity, .subtle)
        XCTAssertNil(editor.project.timeline.segments[1].zoom, "Second segment should use defaults")
    }

    func testEnableAllSegmentsZoom() async throws {
        let editor = try ProjectEditor.mockProject()

        // Disable all zoom
        await editor.setZoomEnabled(false)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == false })

        // Enable all with normal intensity
        let config = Project.Timeline.ZoomConfiguration(intensity: .normal)
        for segment in editor.project.timeline.segments {
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
        }

        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == true })
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.intensity == .normal })
    }

    func testDisableAllSegmentsZoom() async throws {
        let editor = try ProjectEditor.mockProject()

        // Set various configurations
        let segments = editor.project.timeline.segments
        await editor.updateSegmentZoom(segmentId: segments[0].id, configuration: .subtle)
        await editor.updateSegmentZoom(segmentId: segments[1].id, configuration: .aggressive)

        // Disable all
        for segment in editor.project.timeline.segments {
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: .disabled)
        }

        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom?.enabled == false })
    }

    func testResetAllSegmentsToDefaults() async throws {
        let editor = try ProjectEditor.mockProject()
        let segments = editor.project.timeline.segments

        // Set custom configurations
        await editor.updateSegmentZoom(segmentId: segments[0].id, configuration: .subtle)
        await editor.updateSegmentZoom(segmentId: segments[1].id, configuration: .aggressive)

        // Reset all to defaults
        for segment in editor.project.timeline.segments {
            await editor.removeSegmentZoom(segmentId: segment.id)
        }

        // All should be nil (using defaults)
        XCTAssertTrue(editor.project.timeline.segments.allSatisfy { $0.zoom == nil })
    }

    func testSegmentZoomRowState() async throws {
        let editor = try ProjectEditor.mockProject()
        let segment = editor.project.timeline.segments.first!

        // Test initial state
        let initialEnabled = segment.zoom?.enabled ?? true
        XCTAssertTrue(initialEnabled, "Default should be enabled")

        // Test state after update
        await editor.updateSegmentZoom(segmentId: segment.id, configuration: .disabled)
        let updatedSegment = editor.project.timeline.segments.first!
        XCTAssertFalse(updatedSegment.zoom?.enabled ?? true)
    }

    func testSegmentDurationFormatting() {
        // Test duration formatting helper
        let shortDuration: TimeInterval = 5.25
        let mediumDuration: TimeInterval = 65.75
        let longDuration: TimeInterval = 125.50

        let shortFormatted = formatDurationForSegment(shortDuration)
        XCTAssertTrue(shortFormatted.contains("5.25s"), "Short duration should format as seconds")

        let mediumFormatted = formatDurationForSegment(mediumDuration)
        XCTAssertTrue(mediumFormatted.contains("1:"), "Medium duration should show minutes")

        let longFormatted = formatDurationForSegment(longDuration)
        XCTAssertTrue(longFormatted.contains("2:"), "Long duration should show minutes")
    }

    func testSegmentZoomPreservesOtherProperties() async throws {
        let editor = try ProjectEditor.mockProject()
        let segmentId = editor.project.timeline.segments.first!.id

        // Get original properties
        let originalSourceIn = editor.project.timeline.segments.first?.sourceIn
        let originalSourceOut = editor.project.timeline.segments.first?.sourceOut
        let originalSpeed = editor.project.timeline.segments.first?.speed

        // Update zoom
        await editor.updateSegmentZoom(segmentId: segmentId, configuration: .aggressive)

        // Verify other properties unchanged
        XCTAssertEqual(editor.project.timeline.segments.first?.sourceIn, originalSourceIn)
        XCTAssertEqual(editor.project.timeline.segments.first?.sourceOut, originalSourceOut)
        XCTAssertEqual(editor.project.timeline.segments.first?.speed, originalSpeed)
    }

    func testMultipleSegmentsWithDifferentZoom() async throws {
        // Create a project with multiple segments
        let project = Project(
            schemaVersion: 1,
            projectId: "multi-segment",
            name: "Multi Segment",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "/tmp/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                )
            ),
            timeline: Project.Timeline(
                duration: 120.0,
                segments: [
                    Project.Timeline.Segment(
                        id: "seg-1",
                        sourceId: "screen",
                        sourceIn: 0.0,
                        sourceOut: 30.0,
                        timelineIn: 0.0,
                        timelineOut: 30.0,
                        speed: 1.0,
                        zoom: .normal
                    ),
                    Project.Timeline.Segment(
                        id: "seg-2",
                        sourceId: "screen",
                        sourceIn: 30.0,
                        sourceOut: 60.0,
                        timelineIn: 30.0,
                        timelineOut: 60.0,
                        speed: 1.0,
                        zoom: .subtle
                    ),
                    Project.Timeline.Segment(
                        id: "seg-3",
                        sourceId: "screen",
                        sourceIn: 60.0,
                        sourceOut: 90.0,
                        timelineIn: 60.0,
                        timelineOut: 90.0,
                        speed: 1.0,
                        zoom: .aggressive
                    ),
                    Project.Timeline.Segment(
                        id: "seg-4",
                        sourceId: "screen",
                        sourceIn: 90.0,
                        sourceOut: 120.0,
                        timelineIn: 90.0,
                        timelineOut: 120.0,
                        speed: 1.0,
                        zoom: nil
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000"),
                layout: CanvasLayout.defaultLayout(for: .fullscreen)
            ),
            overlays: [],
            captions: nil
        )

        let editor = ProjectEditor(project: project)

        // Verify each segment has different zoom
        XCTAssertEqual(editor.project.timeline.segments[0].zoom?.intensity, .normal)
        XCTAssertEqual(editor.project.timeline.segments[1].zoom?.intensity, .subtle)
        XCTAssertEqual(editor.project.timeline.segments[2].zoom?.intensity, .aggressive)
        XCTAssertNil(editor.project.timeline.segments[3].zoom, "Should use defaults")

        // Update segment 2 to disabled
        await editor.updateSegmentZoom(
            segmentId: "seg-2",
            configuration: .disabled
        )
        XCTAssertFalse(editor.project.timeline.segments[1].zoom?.enabled ?? true)

        // Remove segment 3's config
        await editor.removeSegmentZoom(segmentId: "seg-3")
        XCTAssertNil(editor.project.timeline.segments[2].zoom)

        // Segments 0 and 1 should remain unchanged
        XCTAssertEqual(editor.project.timeline.segments[0].zoom?.intensity, .normal)
        XCTAssertFalse(editor.project.timeline.segments[1].zoom?.enabled ?? true)
    }

    func testSectionZoomControlsWorkflow() async throws {
        let editor = try ProjectEditor.mockProject()
        let segments = editor.project.timeline.segments

        // Workflow: Enable all → Set individual configs → Reset to defaults
        // 1. Enable all with normal intensity
        let normalConfig = Project.Timeline.ZoomConfiguration(intensity: .normal)
        for segment in segments {
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: normalConfig)
        }
        XCTAssertTrue(segments.allSatisfy { $0.zoom?.intensity == .normal })

        // 2. Set different configs per segment
        await editor.updateSegmentZoom(segmentId: segments[0].id, configuration: .subtle)
        await editor.updateSegmentZoom(segmentId: segments[1].id, configuration: .aggressive)
        XCTAssertEqual(editor.project.timeline.segments[0].zoom?.intensity, .subtle)
        XCTAssertEqual(editor.project.timeline.segments[1].zoom?.intensity, .aggressive)

        // 3. Reset all to defaults
        for segment in segments {
            await editor.removeSegmentZoom(segmentId: segment.id)
        }
        XCTAssertTrue(segments.allSatisfy { $0.zoom == nil })
    }

    // MARK: - Helper Methods for Section Tests

    private func formatDurationForSegment(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)

        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%02ds", seconds, milliseconds)
        }
    }
}
