//
//  OverlayEditorViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-G — Overlay Editor (P0)
//

import XCTest
import SwiftUI
@testable import App
import EngineKit
import CoreGraphics

@MainActor
final class OverlayEditorViewTests: XCTestCase {
    var mockProject: Project!
    var mockEditor: ProjectEditor!

    override func setUp() async throws {
        try await super.setUp()

        // Create a mock project
        mockProject = Project(
            id: UUID().uuidString,
            name: "Test Project",
            createdAt: Date(),
            updatedAt: Date(),
            duration: 60.0,
            canvas: Project.Canvas(
                format: Project.Canvas.Format(w: 1920, h: 1080),
                layout: CanvasLayout.defaultLayout(for: .fullscreen),
                background: CanvasLayout.createSolidBackground(hexColor: "#000000")
            ),
            sources: Project.Sources(
                screen: nil,
                camera: nil,
                systemAudio: nil,
                micAudio: nil
            ),
            timeline: Project.Timeline(segments: []),
            overlays: [],
            transcripts: []
        )

        mockEditor = ProjectEditor(project: mockProject)
    }

    // MARK: - Helper Methods

    private func createOverlayStyle(
        stroke: String = "#FFFFFF",
        strokeWidth: Double = 3.0,
        shadow: Bool = true,
        font: String? = nil,
        size: Double? = nil,
        color: String? = nil,
        bg: String? = nil,
        text: String? = nil
    ) -> Project.Overlay.Style {
        var style = Project.Overlay.Style()
        style.stroke = stroke
        style.strokeWidth = strokeWidth
        style.shadow = shadow
        style.font = font
        style.size = size
        style.color = color
        style.bg = bg
        style.text = text
        return style
    }

    private func createOverlayTransform(
        x: Double = 0.5,
        y: Double = 0.5,
        scale: Double = 1.0,
        rotation: Double = 0.0
    ) -> Project.Overlay.Transform {
        var transform = Project.Overlay.Transform()
        transform.x = x
        transform.y = y
        transform.scale = scale
        transform.rotation = rotation
        return transform
    }

    private func createCameraPosition(
        x: Double = 0.5,
        y: Double = 0.5,
        w: Double = 0.3,
        h: Double = 0.3,
        cornerRadius: Double = 8.0
    ) -> Project.Canvas.Layout.CameraPosition {
        var position = Project.Canvas.Layout.CameraPosition()
        position.x = x
        position.y = y
        position.w = w
        position.h = h
        position.cornerRadius = cornerRadius
        return position
    }

    // MARK: - Overlay Creation Tests

    func testOverlayCreation_Arrow() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: createOverlayTransform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: createOverlayStyle(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(
            projectId: mockProject.id,
            overlay: overlay
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should have one overlay")
            XCTAssertEqual(project.overlays.first?.type, .arrow, "Overlay type should be arrow")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayCreation_Rectangle() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#007AFF",
                strokeWidth: 2.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: "#007AFF",
                text: nil
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(
            projectId: mockProject.id,
            overlay: overlay
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should have one overlay")
            XCTAssertEqual(project.overlays.first?.type, .rect, "Overlay type should be rect")
            XCTAssertEqual(project.overlays.first?.style.bg, "#007AFF", "Background should be set")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayCreation_Line() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .line,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF9500",
                strokeWidth: 2.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(
            projectId: mockProject.id,
            overlay: overlay
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should have one overlay")
            XCTAssertEqual(project.overlays.first?.type, .line, "Overlay type should be line")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayCreation_Text() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#000000",
                bg: nil,
                text: "Sample Text"
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(
            projectId: mockProject.id,
            overlay: overlay
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should have one overlay")
            XCTAssertEqual(project.overlays.first?.type, .text, "Overlay type should be text")
            XCTAssertEqual(project.overlays.first?.style.text, "Sample Text", "Text should be set")
            XCTAssertEqual(project.overlays.first?.style.font, "Helvetica", "Font should be set")
            XCTAssertEqual(project.overlays.first?.style.size, 24.0, "Size should be set")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    // MARK: - Overlay Update Tests

    func testOverlayUpdate_Transform() async throws {
        // Create an overlay first
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        // Update transform
        let updatedTransform = Project.Overlay.Transform(x: 0.7, y: 0.7, scale: 1.5, rotation: 45.0)
        let result = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            transform: updatedTransform
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should still have one overlay")
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.transform.x, 0.7, accuracy: 0.001, "X position should be updated")
            XCTAssertEqual(updatedOverlay?.transform.y, 0.7, accuracy: 0.001, "Y position should be updated")
            XCTAssertEqual(updatedOverlay?.transform.scale, 1.5, accuracy: 0.001, "Scale should be updated")
            XCTAssertEqual(updatedOverlay?.transform.rotation, 45.0, accuracy: 0.001, "Rotation should be updated")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayUpdate_Style() async throws {
        // Create an overlay first
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        // Update style
        let updatedStyle = Project.Overlay.Style(
            stroke: "#00C7BE",
            strokeWidth: 5.0,
            shadow: false,
            font: nil,
            size: nil,
            color: nil,
            bg: nil,
            text: nil
        )
        let result = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            style: updatedStyle
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should still have one overlay")
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.style.stroke, "#00C7BE", "Stroke color should be updated")
            XCTAssertEqual(updatedOverlay?.style.strokeWidth, 5.0, accuracy: 0.001, "Stroke width should be updated")
            XCTAssertEqual(updatedOverlay?.style.shadow, false, "Shadow should be disabled")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayUpdate_Timing() async throws {
        // Create an overlay first
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        // Update timing
        let result = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            start: 2.0,
            end: 8.0
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should still have one overlay")
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.start, 2.0, accuracy: 0.001, "Start time should be updated")
            XCTAssertEqual(updatedOverlay?.end, 8.0, accuracy: 0.001, "End time should be updated")
            XCTAssertEqual(updatedOverlay?.end - updatedOverlay!.start, 6.0, accuracy: 0.001, "Duration should be 6 seconds")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayUpdate_TextSpecificStyle() async throws {
        // Create a text overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#000000",
                bg: nil,
                text: "Original Text"
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        // Update text-specific style
        let updatedStyle = Project.Overlay.Style(
            stroke: "#FF3B30",
            strokeWidth: 0.0,
            shadow: true,
            font: "Arial",
            size: 36.0,
            color: "#FF3B30",
            bg: "#FFFFFF",
            text: "Updated Text"
        )
        let result = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            style: updatedStyle
        )

        switch result {
        case .success(let project):
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.style.text, "Updated Text", "Text should be updated")
            XCTAssertEqual(updatedOverlay?.style.font, "Arial", "Font should be updated")
            XCTAssertEqual(updatedOverlay?.style.size, 36.0, accuracy: 0.001, "Size should be updated")
            XCTAssertEqual(updatedOverlay?.style.color, "#FF3B30", "Color should be updated")
            XCTAssertEqual(updatedOverlay?.style.bg, "#FFFFFF", "Background should be updated")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    // MARK: - Overlay Deletion Tests

    func testOverlayDelete() async throws {
        // Create an overlay first
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        XCTAssertEqual(mockEditor.project.overlays.count, 1, "Should have one overlay before deletion")

        // Delete overlay
        let result = await mockEditor.deleteOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id
        )

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 0, "Should have no overlays after deletion")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayDelete_NotFound() async throws {
        let nonExistentId = UUID()

        let result = await mockEditor.deleteOverlay(
            projectId: mockProject.id,
            overlayId: nonExistentId
        )

        switch result {
        case .failure(let error):
            // Expected to fail
            XCTAssertNotNil(error, "Should return an error for non-existent overlay")
        case .success:
            XCTFail("Expected failure for non-existent overlay")
        }
    }

    // MARK: - Multiple Overlays Tests

    func testMultipleOverlays() async throws {
        // Create multiple overlays
        let arrowOverlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.3, y: 0.3, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let textOverlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 2.0,
            end: 7.0,
            transform: Project.Overlay.Transform(x: 0.7, y: 0.7, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#000000",
                bg: nil,
                text: "Label"
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: arrowOverlay)
        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: textOverlay)

        XCTAssertEqual(mockEditor.project.overlays.count, 2, "Should have two overlays")

        // Verify both overlays exist with correct properties
        let arrow = mockEditor.project.overlays.first { $0.type == .arrow }
        let text = mockEditor.project.overlays.first { $0.type == .text }

        XCTAssertNotNil(arrow, "Arrow overlay should exist")
        XCTAssertNotNil(text, "Text overlay should exist")
        XCTAssertEqual(arrow?.start, 0.0, accuracy: 0.001, "Arrow start time should be correct")
        XCTAssertEqual(text?.start, 2.0, accuracy: 0.001, "Text start time should be correct")
    }

    // MARK: - Undo/Redo Tests

    func testOverlayCreationUndoRedo() async throws {
        // Create an overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        XCTAssertEqual(mockEditor.project.overlays.count, 1, "Should have one overlay")
        XCTAssertTrue(mockEditor.canUndo, "Should be able to undo")

        // Undo
        let undoResult = await mockEditor.undo()
        XCTAssertTrue(undoResult, "Undo should succeed")
        XCTAssertEqual(mockEditor.project.overlays.count, 0, "Should have no overlays after undo")
        XCTAssertTrue(mockEditor.canRedo, "Should be able to redo")

        // Redo
        let redoResult = await mockEditor.redo()
        XCTAssertTrue(redoResult, "Redo should succeed")
        XCTAssertEqual(mockEditor.project.overlays.count, 1, "Should have one overlay after redo")
    }

    func testOverlayUpdateUndoRedo() async throws {
        // Create an overlay
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        _ = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        guard let addedOverlay = mockEditor.project.overlays.first else {
            XCTFail("Overlay should be added")
            return
        }

        let originalScale = addedOverlay.transform.scale

        // Update overlay
        let updatedTransform = Project.Overlay.Transform(
            x: addedOverlay.transform.x,
            y: addedOverlay.transform.y,
            scale: 1.5,
            rotation: addedOverlay.transform.rotation
        )
        _ = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            transform: updatedTransform
        )

        XCTAssertEqual(mockEditor.project.overlays.first?.transform.scale, 1.5, accuracy: 0.001, "Scale should be updated")

        // Undo
        let undoResult = await mockEditor.undo()
        XCTAssertTrue(undoResult, "Undo should succeed")
        XCTAssertEqual(mockEditor.project.overlays.first?.transform.scale, originalScale, accuracy: 0.001, "Scale should be restored")

        // Redo
        let redoResult = await mockEditor.redo()
        XCTAssertTrue(redoResult, "Redo should succeed")
        XCTAssertEqual(mockEditor.project.overlays.first?.transform.scale, 1.5, accuracy: 0.001, "Scale should be updated again")
    }

    // MARK: - Overlay Style Extension Tests

    func testOverlayStyleWithMethods() {
        let originalStyle = Project.Overlay.Style(
            stroke: "#FF3B30",
            strokeWidth: 3.0,
            shadow: true,
            font: nil,
            size: nil,
            color: nil,
            bg: nil,
            text: nil
        )

        // Test with(stroke:)
        let updatedStroke = originalStyle.with(stroke: "#00C7BE")
        XCTAssertEqual(originalStyle.stroke, "#FF3B30", "Original style should not be modified")
        XCTAssertEqual(updatedStroke.stroke, "#00C7BE", "Updated style should have new stroke")
        XCTAssertEqual(updatedStroke.strokeWidth, originalStyle.strokeWidth, "Other properties should be preserved")

        // Test with(strokeWidth:)
        let updatedStrokeWidth = originalStyle.with(strokeWidth: 5.0)
        XCTAssertEqual(updatedStrokeWidth.strokeWidth, 5.0, accuracy: 0.001, "Stroke width should be updated")
        XCTAssertEqual(updatedStrokeWidth.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(shadow:)
        let updatedShadow = originalStyle.with(shadow: false)
        XCTAssertEqual(updatedShadow.shadow, false, "Shadow should be updated")
        XCTAssertEqual(updatedShadow.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(font:)
        let updatedFont = originalStyle.with(font: "Arial")
        XCTAssertEqual(updatedFont.font, "Arial", "Font should be updated")
        XCTAssertEqual(updatedFont.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(size:)
        let updatedSize = originalStyle.with(size: 36.0)
        XCTAssertEqual(updatedSize.size, 36.0, accuracy: 0.001, "Size should be updated")
        XCTAssertEqual(updatedSize.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(color:)
        let updatedColor = originalStyle.with(color: "#000000")
        XCTAssertEqual(updatedColor.color, "#000000", "Color should be updated")
        XCTAssertEqual(updatedColor.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(bg:)
        let updatedBg = originalStyle.with(bg: "#FFFFFF")
        XCTAssertEqual(updatedBg.bg, "#FFFFFF", "Background should be updated")
        XCTAssertEqual(updatedBg.stroke, originalStyle.stroke, "Other properties should be preserved")

        // Test with(text:)
        let updatedText = originalStyle.with(text: "New Text")
        XCTAssertEqual(updatedText.text, "New Text", "Text should be updated")
        XCTAssertEqual(updatedText.stroke, originalStyle.stroke, "Other properties should be preserved")
    }

    // MARK: - Overlay Tool Tests

    func testOverlayToolProperties() {
        XCTAssertEqual(OverlayTool.arrow.label, "Arrow", "Arrow tool label should be correct")
        XCTAssertEqual(OverlayTool.arrow.icon, "arrow.up.right", "Arrow tool icon should be correct")
        XCTAssertEqual(OverlayTool.arrow.overlayType, .arrow, "Arrow tool type should be correct")
        XCTAssertEqual(OverlayTool.arrow.shortcut, KeyEquivalent("a"), "Arrow tool shortcut should be 'a'")

        XCTAssertEqual(OverlayTool.rect.label, "Rectangle", "Rectangle tool label should be correct")
        XCTAssertEqual(OverlayTool.rect.icon, "rectangle", "Rectangle tool icon should be correct")
        XCTAssertEqual(OverlayTool.rect.overlayType, .rect, "Rectangle tool type should be correct")
        XCTAssertEqual(OverlayTool.rect.shortcut, KeyEquivalent("r"), "Rectangle tool shortcut should be 'r'")

        XCTAssertEqual(OverlayTool.line.label, "Line", "Line tool label should be correct")
        XCTAssertEqual(OverlayTool.line.icon, "line.diagonal", "Line tool icon should be correct")
        XCTAssertEqual(OverlayTool.line.overlayType, .line, "Line tool type should be correct")
        XCTAssertEqual(OverlayTool.line.shortcut, KeyEquivalent("l"), "Line tool shortcut should be 'l'")

        XCTAssertEqual(OverlayTool.text.label, "Text", "Text tool label should be correct")
        XCTAssertEqual(OverlayTool.text.icon, "textformat", "Text tool icon should be correct")
        XCTAssertEqual(OverlayTool.text.overlayType, .text, "Text tool type should be correct")
        XCTAssertEqual(OverlayTool.text.shortcut, KeyEquivalent("t"), "Text tool shortcut should be 't'")
    }

    // MARK: - Edge Cases Tests

    func testOverlayWithZeroDuration() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 5.0,
            end: 5.0, // Zero duration
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        // Should still allow zero duration overlays (user may extend them later)
        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should allow zero duration overlay")
            XCTAssertEqual(project.overlays.first?.end - project.overlays.first!.start, 0.0, accuracy: 0.001, "Duration should be zero")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testOverlayWithLargeTransformValues() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(x: 2.0, y: -0.5, scale: 5.0, rotation: 720.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should allow large transform values")
            let addedOverlay = project.overlays.first
            XCTAssertEqual(addedOverlay?.transform.x, 2.0, accuracy: 0.001, "X should be preserved")
            XCTAssertEqual(addedOverlay?.transform.y, -0.5, accuracy: 0.001, "Y should be preserved")
            XCTAssertEqual(addedOverlay?.transform.scale, 5.0, accuracy: 0.001, "Scale should be preserved")
            XCTAssertEqual(addedOverlay?.transform.rotation, 720.0, accuracy: 0.001, "Rotation should be preserved")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    // MARK: - Animation Tests (Épica UI-G, P1)

    func testAddOverlayWithFadeInAnimation() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add overlay with fade-in animation")
            let addedOverlay = project.overlays.first
            XCTAssertNotNil(addedOverlay?.animation, "Animation should be set")
            XCTAssertEqual(addedOverlay?.animation?.type, .fadeIn, "Animation type should be fade-in")
            XCTAssertEqual(addedOverlay?.animation?.fadeInDuration, 0.5, accuracy: 0.001, "Fade-in duration should be 0.5s")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAddOverlayWithFadeOutAnimation() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeOut,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.8,
            drawOnDuration: nil,
            easing: .easeOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 2.0,
            end: 8.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#007AFF",
                strokeWidth: 2.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add overlay with fade-out animation")
            let addedOverlay = project.overlays.first
            XCTAssertEqual(addedOverlay?.animation?.type, .fadeOut, "Animation type should be fade-out")
            XCTAssertEqual(addedOverlay?.animation?.fadeOutDuration, 0.8, accuracy: 0.001, "Fade-out duration should be 0.8s")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAddOverlayWithFadeInOutAnimation() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 0.4,
            fadeOutDuration: 0.4,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 1.0,
            end: 6.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#FFFFFF",
                bg: nil,
                text: "Hello World"
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add overlay with fade-in-out animation")
            let addedOverlay = project.overlays.first
            XCTAssertEqual(addedOverlay?.animation?.type, .fadeInOut, "Animation type should be fade-in-out")
            XCTAssertEqual(addedOverlay?.animation?.fadeInDuration, 0.4, accuracy: 0.001, "Fade-in duration should be 0.4s")
            XCTAssertEqual(addedOverlay?.animation?.fadeOutDuration, 0.4, accuracy: 0.001, "Fade-out duration should be 0.4s")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAddOverlayWithDrawOnAnimation() async throws {
        let animation = Project.Overlay.Animation(
            type: .drawOn,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.3,
            drawOnDuration: 1.2,
            easing: .linear
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#FF9500",
                strokeWidth: 4.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add overlay with draw-on animation")
            let addedOverlay = project.overlays.first
            XCTAssertEqual(addedOverlay?.animation?.type, .drawOn, "Animation type should be draw-on")
            XCTAssertEqual(addedOverlay?.animation?.drawOnDuration, 1.2, accuracy: 0.001, "Draw-on duration should be 1.2s")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAddOverlayWithNoAnimation() async throws {
        let overlay = Project.Overlay(
            id: UUID(),
            type: .line,
            start: 0.0,
            end: 3.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#34C759",
                strokeWidth: 2.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add overlay without animation")
            let addedOverlay = project.overlays.first
            XCTAssertNil(addedOverlay?.animation, "Animation should be nil for no animation")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testUpdateOverlayAnimationType() async throws {
        // First add an overlay without animation
        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#5856D6",
                strokeWidth: 3.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let addResult = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)
        guard case .success(let project) = addResult,
              let addedOverlay = project.overlays.first else {
            XCTFail("Failed to add overlay")
            return
        }

        // Update animation to fade-in
        let newAnimation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeIn
        )

        let updateResult = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            animation: newAnimation
        )

        switch updateResult {
        case .success(let project):
            let updatedOverlay = project.overlays.first
            XCTAssertNotNil(updatedOverlay?.animation, "Animation should be set after update")
            XCTAssertEqual(updatedOverlay?.animation?.type, .fadeIn, "Animation type should be updated to fade-in")
            XCTAssertEqual(updatedOverlay?.animation?.easing, .easeIn, "Easing should be updated")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testUpdateOverlayAnimationDuration() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: animation
        )

        let addResult = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)
        guard case .success(let project) = addResult,
              let addedOverlay = project.overlays.first else {
            XCTFail("Failed to add overlay")
            return
        }

        // Update fade-in duration
        let updatedAnimation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 0.8,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let updateResult = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            animation: updatedAnimation
        )

        switch updateResult {
        case .success(let project):
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.animation?.fadeInDuration, 0.8, accuracy: 0.001, "Fade-in duration should be updated")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testUpdateOverlayAnimationEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .linear
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Arial",
                size: 20.0,
                color: "#000000",
                bg: nil,
                text: "Test"
            ),
            animation: animation
        )

        let addResult = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)
        guard case .success(let project) = addResult,
              let addedOverlay = project.overlays.first else {
            XCTFail("Failed to add overlay")
            return
        }

        // Update easing function
        let updatedAnimation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeOut
        )

        let updateResult = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            animation: updatedAnimation
        )

        switch updateResult {
        case .success(let project):
            let updatedOverlay = project.overlays.first
            XCTAssertEqual(updatedOverlay?.animation?.easing, .easeOut, "Easing should be updated to ease-out")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testRemoveOverlayAnimation() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#007AFF",
                strokeWidth: 2.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: animation
        )

        let addResult = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)
        guard case .success(let project) = addResult,
              let addedOverlay = project.overlays.first else {
            XCTFail("Failed to add overlay")
            return
        }

        // Remove animation by setting it to nil
        let updateResult = await mockEditor.updateOverlay(
            projectId: mockProject.id,
            overlayId: addedOverlay.id,
            animation: nil
        )

        switch updateResult {
        case .success(let project):
            let updatedOverlay = project.overlays.first
            XCTAssertNil(updatedOverlay?.animation, "Animation should be removed")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAnimationWithAllEasingFunctions() async throws {
        let easingFunctions: [Project.Overlay.Animation.EasingFunction] = [.linear, .easeIn, .easeOut, .easeInOut]

        for easing in easingFunctions {
            let animation = Project.Overlay.Animation(
                type: .fadeIn,
                fadeInDuration: 0.3,
                fadeOutDuration: 0.3,
                drawOnDuration: nil,
                easing: easing
            )

            let overlay = Project.Overlay(
                id: UUID(),
                type: .arrow,
                start: 0.0,
                end: 3.0,
                transform: Project.Overlay.Transform(),
                style: Project.Overlay.Style(
                    stroke: "#FF3B30",
                    strokeWidth: 3.0,
                    shadow: false,
                    font: nil,
                    size: nil,
                    color: nil,
                    bg: nil,
                    text: nil
                ),
                animation: animation
            )

            let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

            switch result {
            case .success(let project):
                let addedOverlay = project.overlays.last
                XCTAssertEqual(addedOverlay?.animation?.easing, easing, "Easing should be \(easing)")
            case .failure(let error):
                XCTFail("Expected success for easing \(easing), got failure: \(error)")
            }
        }
    }

    func testAnimationWithAllAnimationTypes() async throws {
        let animationTypes: [Project.Overlay.Animation.AnimationType] = [.none, .fadeIn, .fadeOut, .fadeInOut, .drawOn]

        for type in animationTypes {
            let animation = type == .none ? nil : Project.Overlay.Animation(
                type: type,
                fadeInDuration: 0.3,
                fadeOutDuration: 0.3,
                drawOnDuration: type == .drawOn ? 0.8 : nil,
                easing: .easeInOut
            )

            let overlay = Project.Overlay(
                id: UUID(),
                type: .rect,
                start: 0.0,
                end: 4.0,
                transform: Project.Overlay.Transform(),
                style: Project.Overlay.Style(
                    stroke: "#007AFF",
                    strokeWidth: 2.0,
                    shadow: false,
                    font: nil,
                    size: nil,
                    color: nil,
                    bg: nil,
                    text: nil
                ),
                animation: animation
            )

            let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

            switch result {
            case .success(let project):
                let addedOverlay = project.overlays.last
                if type == .none {
                    XCTAssertNil(addedOverlay?.animation, "Animation should be nil for none type")
                } else {
                    XCTAssertEqual(addedOverlay?.animation?.type, type, "Animation type should be \(type)")
                }
            case .failure(let error):
                XCTFail("Expected success for type \(type), got failure: \(error)")
            }
        }
    }

    func testMultipleOverlaysWithDifferentAnimations() async throws {
        var overlayCount = 0

        // Add overlay with fade-in
        let fadeInAnimation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.5,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeIn
        )

        let overlay1 = Project.Overlay(
            id: UUID(),
            type: .arrow,
            start: 0.0,
            end: 3.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: fadeInAnimation
        )

        let result1 = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay1)
        if case .success = result1 { overlayCount += 1 }

        // Add overlay with draw-on
        let drawOnAnimation = Project.Overlay.Animation(
            type: .drawOn,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.3,
            drawOnDuration: 1.0,
            easing: .linear
        )

        let overlay2 = Project.Overlay(
            id: UUID(),
            type: .line,
            start: 3.0,
            end: 6.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#34C759",
                strokeWidth: 2.0,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: drawOnAnimation
        )

        let result2 = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay2)
        if case .success = result2 { overlayCount += 1 }

        // Add overlay without animation
        let overlay3 = Project.Overlay(
            id: UUID(),
            type: .rect,
            start: 6.0,
            end: 9.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#5856D6",
                strokeWidth: 4.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            ),
            animation: nil
        )

        let result3 = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay3)
        if case .success = result3 { overlayCount += 1 }

        // Verify all overlays were added with correct animations
        switch result3 {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, overlayCount, "Should have \(overlayCount) overlays")
            XCTAssertEqual(project.overlays[0].animation?.type, .fadeIn, "First overlay should have fade-in")
            XCTAssertEqual(project.overlays[1].animation?.type, .drawOn, "Second overlay should have draw-on")
            XCTAssertNil(project.overlays[2].animation, "Third overlay should have no animation")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAnimationDefaultValues() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.3,
            drawOnDuration: nil,
            easing: .easeInOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 0.0,
            end: 5.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Courier",
                size: 18.0,
                color: "#000000",
                bg: nil,
                text: "Animation Test"
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            let addedOverlay = project.overlays.first
            XCTAssertNotNil(addedOverlay?.animation, "Animation should be set")
            XCTAssertEqual(addedOverlay?.animation?.fadeInDuration, 0.3, accuracy: 0.001, "Default fade-in should be 0.3s")
            XCTAssertEqual(addedOverlay?.animation?.fadeOutDuration, 0.3, accuracy: 0.001, "Default fade-out should be 0.3s")
            XCTAssertEqual(addedOverlay?.animation?.easing, .easeInOut, "Default easing should be ease-in-out")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }

    func testAnimationWithTextOverlay() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.6,
            fadeOutDuration: 0.4,
            drawOnDuration: nil,
            easing: .easeOut
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: .text,
            start: 1.0,
            end: 6.0,
            transform: Project.Overlay.Transform(),
            style: Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: true,
                font: "Georgia",
                size: 32.0,
                color: "#FFFFFF",
                bg: "#00000080",
                text: "Animated Text"
            ),
            animation: animation
        )

        let result = await mockEditor.addOverlay(projectId: mockProject.id, overlay: overlay)

        switch result {
        case .success(let project):
            XCTAssertEqual(project.overlays.count, 1, "Should add text overlay with animation")
            let addedOverlay = project.overlays.first
            XCTAssertEqual(addedOverlay?.type, .text, "Overlay type should be text")
            XCTAssertEqual(addedOverlay?.animation?.type, .fadeIn, "Text overlay should have fade-in animation")
            XCTAssertEqual(addedOverlay?.style.text, "Animated Text", "Text should be preserved")
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error)")
        }
    }
}
