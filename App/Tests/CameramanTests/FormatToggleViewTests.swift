//
//  FormatToggleViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import SwiftUI
import EngineKit
@testable import Cameraman

@MainActor
final class FormatToggleViewTests: XCTestCase {
    var mockProject: Project!
    var editor: ProjectEditor!

    override func setUp() async throws {
        try await super.setUp()

        mockProject = Project(
            schemaVersion: 1,
            projectId: "test-project-\(UUID().uuidString)",
            name: "Test Project",
            tags: ["test"],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "screen.mov",
                    fps: 60,
                    size: Project.Sources.Size(w: 1920, h: 1080),
                    syncOffsetMs: 0,
                    sha256: "abc123",
                    sizeBytes: 1024000
                ),
                camera: Project.Sources.MediaTrack(
                    path: "camera.mov",
                    fps: 30,
                    size: Project.Sources.Size(w: 1280, h: 720),
                    syncOffsetMs: 0,
                    sha256: "def456",
                    sizeBytes: 512000
                ),
                audio: Project.Sources.AudioTracks(
                    system: Project.Sources.AudioTracks.AudioTrack(
                        path: "system_audio.m4a",
                        syncOffsetMs: 0,
                        sha256: "ghi789",
                        sizeBytes: 256000
                    ),
                    mic: Project.Sources.AudioTracks.AudioTrack(
                        path: "mic_audio.m4a",
                        syncOffsetMs: 0,
                        sha256: "jkl012",
                        sizeBytes: 128000
                    )
                )
            ),
            timeline: Project.Timeline(
                duration: 60.0,
                segments: [
                    Project.Timeline.Segment(
                        id: "segment-1",
                        sourceIn: 0,
                        sourceOut: 60,
                        timelineIn: 0,
                        speed: 1.0
                    )
                ]
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(
                    type: "solid",
                    value: "#000000",
                    fitMode: nil
                ),
                layout: Project.Canvas.Layout(
                    type: "fullscreen",
                    camera: nil
                )
            ),
            overlays: [],
            captions: nil
        )

        editor = ProjectEditor(project: mockProject)
    }

    // MARK: - Format Toggle Tests

    func testSetFormatToLandscape16_9() async throws {
        // Set to 16:9
        let success = await editor.setFormat(.landscape16_9)

        XCTAssertTrue(success, "Setting format to 16:9 should succeed")
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")
        XCTAssertEqual(editor.project.canvas.format.w, 1920)
        XCTAssertEqual(editor.project.canvas.format.h, 1080)
    }

    func testSetFormatToPortrait9_16() async throws {
        // Set to 9:16
        let success = await editor.setFormat(.portrait9_16)

        XCTAssertTrue(success, "Setting format to 9:16 should succeed")
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")
        XCTAssertEqual(editor.project.canvas.format.w, 607)
        XCTAssertEqual(editor.project.canvas.format.h, 3402)
    }

    func testSetFormatToSquare1_1() async throws {
        // Set to 1:1
        let success = await editor.setFormat(.square1_1)

        XCTAssertTrue(success, "Setting format to 1:1 should succeed")
        XCTAssertEqual(editor.project.canvas.format.aspect, "1:1")
        XCTAssertEqual(editor.project.canvas.format.w, 1080)
        XCTAssertEqual(editor.project.canvas.format.h, 1080)
    }

    func testSetFormatToLandscape4_3() async throws {
        // Set to 4:3
        let success = await editor.setFormat(.landscape4_3)

        XCTAssertTrue(success, "Setting format to 4:3 should succeed")
        XCTAssertEqual(editor.project.canvas.format.aspect, "4:3")
        XCTAssertEqual(editor.project.canvas.format.w, 1440)
        XCTAssertEqual(editor.project.canvas.format.h, 1080)
    }

    func testFormatToggleBetweenLandscapeAndPortrait() async throws {
        // Start with 16:9
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")

        // Switch to 9:16
        let success1 = await editor.setFormat(.portrait9_16)
        XCTAssertTrue(success1)
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")
        XCTAssertEqual(editor.project.canvas.format.w, 607)
        XCTAssertEqual(editor.project.canvas.format.h, 3402)

        // Switch back to 16:9
        let success2 = await editor.setFormat(.landscape16_9)
        XCTAssertTrue(success2)
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")
        XCTAssertEqual(editor.project.canvas.format.w, 1920)
        XCTAssertEqual(editor.project.canvas.format.h, 1080)
    }

    // MARK: - Undo/Redo Tests

    func testSetFormatRecordsUndoSnapshot() async throws {
        let originalFormat = editor.project.canvas.format

        // Change format
        _ = await editor.setFormat(.portrait9_16)

        // Verify undo is available
        XCTAssertTrue(editor.canUndo, "Undo should be available after format change")

        // Undo the change
        _ = await editor.undo()

        // Verify format is restored
        XCTAssertEqual(editor.project.canvas.format.aspect, originalFormat.aspect)
        XCTAssertEqual(editor.project.canvas.format.w, originalFormat.w)
        XCTAssertEqual(editor.project.canvas.format.h, originalFormat.h)
    }

    func testSetFormatUndoRedo() async throws {
        // Start with 16:9
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")

        // Change to 9:16
        _ = await editor.setFormat(.portrait9_16)
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")

        // Undo
        _ = await editor.undo()
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")

        // Redo
        _ = await editor.redo()
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")
    }

    // MARK: - Integration Tests

    func testSetFormatPreservesOtherCanvasProperties() async throws {
        let originalBackground = editor.project.canvas.background
        let originalLayout = editor.project.canvas.layout

        // Change format
        _ = await editor.setFormat(.portrait9_16)

        // Verify other properties are preserved
        XCTAssertEqual(editor.project.canvas.background.type, originalBackground.type)
        XCTAssertEqual(editor.project.canvas.background.value, originalBackground.value)
        XCTAssertEqual(editor.project.canvas.layout.type, originalLayout.type)
        XCTAssertEqual(editor.project.canvas.layout.camera, originalLayout.camera)
    }

    func testSetFormatWithOverlays() async throws {
        // Add an overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0,
            end: 5,
            transform: Project.Overlay.Transform(x: 100, y: 100, scale: 1, rotation: 0),
            style: Project.Overlay.Style(stroke: "#FF0000", strokeWidth: 2, shadow: false),
            animation: nil
        )
        _ = await editor.addOverlay(projectId: mockProject.projectId, overlay: overlay)

        // Change format
        let success = await editor.setFormat(.portrait9_16)

        // Verify format changed and overlays are preserved
        XCTAssertTrue(success)
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")
        XCTAssertEqual(editor.project.overlays.count, 1)
        XCTAssertEqual(editor.project.overlays.first?.id, overlay.id)
    }

    func testSetFormatWithTimelineEdits() async throws {
        // Make a timeline edit
        _ = await editor.split(segmentId: "segment-1", at: 30.0)

        let initialSegmentCount = editor.project.timeline.segments.count

        // Change format
        let success = await editor.setFormat(.portrait9_16)

        // Verify format changed and timeline edits are preserved
        XCTAssertTrue(success)
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")
        XCTAssertEqual(editor.project.timeline.segments.count, initialSegmentCount)
    }

    func testMultipleFormatChanges() async throws {
        // Make multiple format changes
        _ = await editor.setFormat(.portrait9_16)
        XCTAssertEqual(editor.project.canvas.format.aspect, "9:16")

        _ = await editor.setFormat(.square1_1)
        XCTAssertEqual(editor.project.canvas.format.aspect, "1:1")

        _ = await editor.setFormat(.landscape4_3)
        XCTAssertEqual(editor.project.canvas.format.aspect, "4:3")

        _ = await editor.setFormat(.landscape16_9)
        XCTAssertEqual(editor.project.canvas.format.aspect, "16:9")

        // Verify undo stack has all changes
        XCTAssertTrue(editor.canUndo)
    }

    // MARK: - CanvasLayout Tests

    func testCanvasLayoutCreateFormatFor16_9() {
        let format = CanvasLayout.createFormat(for: .landscape16_9)

        XCTAssertEqual(format.aspect, "16:9")
        XCTAssertEqual(format.w, 1920)
        XCTAssertEqual(format.h, 1080)
    }

    func testCanvasLayoutCreateFormatFor9_16() {
        let format = CanvasLayout.createFormat(for: .portrait9_16)

        XCTAssertEqual(format.aspect, "9:16")
        XCTAssertEqual(format.w, 607)
        XCTAssertEqual(format.h, 3402)
    }

    func testCanvasLayoutCreateFormatFor1_1() {
        let format = CanvasLayout.createFormat(for: .square1_1)

        XCTAssertEqual(format.aspect, "1:1")
        XCTAssertEqual(format.w, 1080)
        XCTAssertEqual(format.h, 1080)
    }

    func testCanvasLayoutCreateFormatFor4_3() {
        let format = CanvasLayout.createFormat(for: .landscape4_3)

        XCTAssertEqual(format.aspect, "4:3")
        XCTAssertEqual(format.w, 1440)
        XCTAssertEqual(format.h, 1080)
    }

    func testCanvasLayoutValidateFormat() throws {
        let validFormat = Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080)

        // Should not throw
        try CanvasLayout.validateFormat(validFormat)
    }

    func testCanvasLayoutValidateInvalidFormat() throws {
        let invalidFormat = Project.Canvas.Format(aspect: "invalid", w: 1920, h: 1080)

        // Should throw
        XCTAssertThrowsError(try CanvasLayout.validateFormat(invalidFormat)) { error in
            XCTAssertTrue(error is CanvasLayout.LayoutError)
        }
    }

    // MARK: - AspectRatio Enum Tests

    func testAspectRatioDisplayName() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.displayName, "16:9")
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.displayName, "9:16")
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.displayName, "1:1")
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.displayName, "4:3")
    }

    func testAspectRatioWidthForHeight() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.width(for: 1080), 1920)
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.width(for: 1080), 607)
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.width(for: 1080), 1080)
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.width(for: 1080), 1440)
    }

    func testAspectRatioHeightForWidth() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.height(for: 1920), 1080)
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.height(for: 1920), 3402)
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.height(for: 1080), 1080)
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.height(for: 1440), 1080)
    }

    // MARK: - PreviewPlayerViewModel Tests

    func testPreviewPlayerViewModelAspectRatio() async {
        let viewModel = PreviewPlayerViewModel()

        // Load project with 16:9 format
        viewModel.load(project: mockProject, projectDirectory: nil)

        // Should use canvas format aspect ratio
        XCTAssertEqual(viewModel.aspectRatio, 16.0 / 9.0)
    }

    func testPreviewPlayerViewModelAspectRatioFor9_16() async {
        let viewModel = PreviewPlayerViewModel()

        // Create project with 9:16 format
        var project = mockProject
        project.canvas.format = Project.Canvas.Format(aspect: "9:16", w: 607, h: 3402)

        viewModel.load(project: project, projectDirectory: nil)

        // Should use canvas format aspect ratio
        XCTAssertEqual(viewModel.aspectRatio, 607.0 / 3402.0, accuracy: 0.01)
    }

    // MARK: - Performance Tests

    func testFormatTogglePerformance() async throws {
        measure {
            Task {
                for _ in 0..<10 {
                    _ = await editor.setFormat(.portrait9_16)
                    _ = await editor.setFormat(.landscape16_9)
                }
            }
        }
    }
}
