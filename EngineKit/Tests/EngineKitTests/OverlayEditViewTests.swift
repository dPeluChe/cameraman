//
//  OverlayEditViewTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for overlay editing operations in EditorModel
final class OverlayEditViewTests: XCTestCase {

    var project: Project!
    var editorModel: EditorModel!

    override func setUp() async throws {
        try await super.setUp()

        // Create a test project
        project = Project(
            projectId: UUID(),
            name: "Test Project",
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "sources/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 524288000
                ),
                camera: Project.Sources.MediaTrack(
                    path: "sources/camera.mov",
                    fps: 30.0,
                    size: Project.Sources.Size(w: 1280, h: 720),
                    syncOffsetMs: 0,
                    sha256: "def456",
                    sizeBytes: 104857600
                ),
                audio: Project.Sources.AudioTracks(
                    system: Project.Sources.AudioTracks.AudioTrack(
                        path: "sources/system_audio.m4a",
                        syncOffsetMs: 0,
                        sha256: "ghi789",
                        sizeBytes: 10485760
                    ),
                    mic: Project.Sources.AudioTracks.AudioTrack(
                        path: "sources/mic_audio.m4a",
                        syncOffsetMs: 0,
                        sha256: "jkl012",
                        sizeBytes: 10485760
                    )
                ),
                telemetry: Project.Sources.TelemetryTracks(
                    cursor: Project.Sources.TelemetryTracks.TelemetryTrack(path: "telemetry/cursor.jsonl"),
                    keys: Project.Sources.TelemetryTracks.TelemetryTrack(path: "telemetry/keys.jsonl")
                )
            ),
            timeline: Project.Timeline(
                duration: 120.0,
                segments: [
                    Project.Timeline.Segment(
                        id: "seg-1",
                        sourceIn: 0.0,
                        sourceOut: 60.0,
                        timelineIn: 0.0,
                        speed: 1.0
                    ),
                    Project.Timeline.Segment(
                        id: "seg-2",
                        sourceIn: 60.0,
                        sourceOut: 120.0,
                        timelineIn: 60.0,
                        speed: 1.0
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
                layout: Project.Canvas.Layout(
                    type: "pip",
                    camera: Project.Canvas.Layout.CameraPosition(x: 0.74, y: 0.72, w: 0.22, h: 0.22, cornerRadius: 18)
                )
            ),
            overlays: [],
            captions: nil,
            tags: ["test"],
            schemaVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )

        editorModel = EditorModel(project: project)
    }

    // MARK: - Update Overlay Transform Tests

    func testUpdateOverlayPosition() async throws {
        // Create an arrow overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let updatedProject = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(updatedProject)

        // Update position
        let newTransform = Project.Overlay.Transform(x: 0.6, y: 0.7, scale: 1.0, rotation: 0.0)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            transform: newTransform
        )

        let updatedProjectResult = await editorModel.getProject()
        let updatedOverlay = updatedProjectResult.overlays.first(where: { $0.id == overlay.id })
        XCTAssertNotNil(updatedOverlay)
        XCTAssertEqual(updatedOverlay?.transform.x, 0.6)
        XCTAssertEqual(updatedOverlay?.transform.y, 0.7)
    }

    func testUpdateOverlayScale() async throws {
        // Create a rectangle overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 10.0,
            end: 20.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let updatedProject = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(updatedProject)

        // Update scale
        let newTransform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.5, rotation: 0.0)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            transform: newTransform
        )

        let projectResult = await editorModel.getProject()
        let updatedOverlay = projectResult.overlays.first(where: { $0.id == overlay.id })
        XCTAssertEqual(updatedOverlay?.transform.scale, 1.5)
    }

    // MARK: - Update Overlay Style Tests

    func testUpdateOverlayStrokeColor() async throws {
        // Create an arrow overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let updatedProject = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(updatedProject)

        // Update stroke color
        let newStyle = Project.Overlay.Style(stroke: "#FF0000", strokeWidth: 6.0, shadow: true)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            style: newStyle
        )

        let projectResult = await editorModel.getProject()
        let updatedOverlay = projectResult.overlays.first(where: { $0.id == overlay.id })
        XCTAssertEqual(updatedOverlay?.style.stroke, "#FF0000")
    }

    func testUpdateOverlayStrokeWidth() async throws {
        // Create a rectangle overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 10.0,
            end: 20.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let projectWithOverlay = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlay)

        // Update stroke width
        let newStyle = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 10.0, shadow: true)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            style: newStyle
        )

        let projectResult = await editorModel.getProject()
        let updatedOverlay = projectResult.overlays.first(where: { $0.id == overlay.id })
        XCTAssertEqual(updatedOverlay?.style.strokeWidth, 10.0)
    }

    func testUpdateOverlayShadow() async throws {
        // Create a line overlay with shadow enabled
        let overlay = Project.Overlay(
            id: UUID(),
            type: .line,
            start: 15.0,
            end: 25.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let projectWithOverlay = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlay)

        let currentProject = await editorModel.getProject()
        XCTAssertNotNil(currentProject)

        // Disable shadow
        let newStyle = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: false)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            style: newStyle
        )

        let projectResult = await editorModel.getProject()
        let updatedOverlay = projectResult.overlays.first(where: { $0.id == overlay.id })
        XCTAssertNotNil(updatedOverlay)
        XCTAssertFalse(updatedOverlay!.style.shadow)
    }

    // MARK: - Delete Overlay Tests

    func testDeleteOverlay() async throws {
        // Create two overlays
        let overlay1 = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        let overlay2 = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 10.0,
            end: 20.0,
            transform: Project.Overlay.Transform(x: 0.6, y: 0.6, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: true),
            animation: nil
        )

        // Create a new project with overlays
        let projectWithOverlays = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay1, overlay2],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlays)

        let projectBeforeDelete = await editorModel.getProject()
        XCTAssertEqual(projectBeforeDelete.overlays.count, 2)

        // Delete first overlay
        _ = await editorModel.deleteOverlay(
            projectId: project.projectId,
            overlayId: overlay1.id
        )

        let projectAfterDelete = await editorModel.getProject()
        XCTAssertEqual(projectAfterDelete.overlays.count, 1)
        XCTAssertNil(projectAfterDelete.overlays.first(where: { $0.id == overlay1.id }))
        XCTAssertNotNil(projectAfterDelete.overlays.first(where: { $0.id == overlay2.id }))
    }

    func testDeleteLastOverlay() async throws {
        // Create a single overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let projectWithOverlay = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlay)

        let projectBeforeDelete = await editorModel.getProject()
        XCTAssertEqual(projectBeforeDelete.overlays.count, 1)

        // Delete the only overlay
        _ = await editorModel.deleteOverlay(
            projectId: project.projectId,
            overlayId: overlay.id
        )

        let projectAfterDelete = await editorModel.getProject()
        XCTAssertTrue(projectAfterDelete.overlays.isEmpty)
    }

    // MARK: - Error Handling Tests

    func testUpdateOverlayWithNonExistentId() async throws {
        // Try to update an overlay that doesn't exist
        let fakeId = UUID()
        let newTransform = Project.Overlay.Transform(x: 0.6, y: 0.7, scale: 1.0, rotation: 0.0)

        let result = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: fakeId,
            transform: newTransform
        )

        switch result {
        case .success:
            XCTFail("Expected failure for non-existent overlay")
        case .successWithInfo:
            XCTFail("Expected failure for non-existent overlay")
        case .failure(let error):
            // Expected
            XCTAssertEqual(error.localizedDescription, "Segment with ID '\(fakeId.uuidString)' not found")
        }
    }

    func testDeleteOverlayWithNonExistentId() async throws {
        // Try to delete an overlay that doesn't exist
        let fakeId = UUID()

        let result = await editorModel.deleteOverlay(
            projectId: project.projectId,
            overlayId: fakeId
        )

        switch result {
        case .success:
            XCTFail("Expected failure for non-existent overlay")
        case .successWithInfo:
            XCTFail("Expected failure for non-existent overlay")
        case .failure(let error):
            // Expected
            XCTAssertEqual(error.localizedDescription, "Segment with ID '\(fakeId.uuidString)' not found")
        }
    }

    // MARK: - Project Timestamp Update Tests

    func testProjectTimestampUpdatedAfterOverlayUpdate() async throws {
        // Create an overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let projectWithOverlay = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlay)

        let projectBeforeUpdate = await editorModel.getProject()
        let originalUpdatedAt = projectBeforeUpdate.updatedAt

        // Wait a tiny bit to ensure timestamp difference
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Update overlay
        let newTransform = Project.Overlay.Transform(x: 0.6, y: 0.7, scale: 1.0, rotation: 0.0)
        _ = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            transform: newTransform
        )

        let projectAfterUpdate = await editorModel.getProject()
        XCTAssertGreaterThan(projectAfterUpdate.updatedAt, originalUpdatedAt)
    }

    func testProjectTimestampUpdatedAfterOverlayDelete() async throws {
        // Create an overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true),
            animation: nil
        )

        // Create a new project with the overlay
        let projectWithOverlay = Project(
            projectId: project.projectId,
            name: project.name,
            sources: project.sources,
            timeline: project.timeline,
            canvas: project.canvas,
            overlays: [overlay],
            captions: project.captions,
            tags: project.tags,
            schemaVersion: project.schemaVersion,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        await editorModel.setProject(projectWithOverlay)

        let projectBeforeDelete = await editorModel.getProject()
        let originalUpdatedAt = projectBeforeDelete.updatedAt

        // Wait a tiny bit to ensure timestamp difference
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Delete overlay
        _ = await editorModel.deleteOverlay(
            projectId: project.projectId,
            overlayId: overlay.id
        )

        let projectAfterDelete = await editorModel.getProject()
        XCTAssertGreaterThan(projectAfterDelete.updatedAt, originalUpdatedAt)
    }
}
