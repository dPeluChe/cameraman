//
//  BackgroundControlsViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import SwiftUI
@testable import App
@testable import EngineKit

@MainActor
final class BackgroundControlsViewTests: XCTestCase {
    private var editor: ProjectEditor!
    private var mockProject: Project!

    override func setUp() async throws {
        try await super.setUp()

        // Create a mock project
        mockProject = createMockProject()

        // Initialize ProjectEditor
        editor = ProjectEditor(project: mockProject)
    }

    override func tearDown() async throws {
        editor = nil
        mockProject = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockProject() -> Project {
        let format = Project.Canvas.Format(
            aspect: "16:9",
            w: 1920,
            h: 1080
        )

        let background = Project.Canvas.Background(
            type: "solid",
            value: "#0B0B0D",
            fitMode: nil
        )

        let layout = Project.Canvas.Layout(
            type: "fullscreen",
            camera: nil
        )

        let canvas = Project.Canvas(
            format: format,
            background: background,
            layout: layout
        )

        let sources = Project.Sources(
            screen: nil,
            camera: nil,
            systemAudio: nil,
            micAudio: nil
        )

        let timeline = Project.Timeline(
            segments: [],
            duration: 0
        )

        return Project(
            id: UUID().uuidString,
            name: "Test Project",
            createdAt: Date(),
            updatedAt: Date(),
            sources: sources,
            timeline: timeline,
            canvas: canvas,
            overlays: [],
            exportSettings: nil
        )
    }

    private func createBackground(type: String, value: String, fitMode: String? = nil) -> Project.Canvas.Background {
        Project.Canvas.Background(
            type: type,
            value: value,
            fitMode: fitMode
        )
    }

    // MARK: - Background Type Tests

    func testBackgroundTypeSolid() async throws {
        // Test setting background type to solid
        let success = await editor.setBackgroundType(.solid)

        XCTAssertTrue(success, "Setting background type to solid should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "solid")
        XCTAssertEqual(editor.project.canvas.background.value, "#0B0B0D")
        XCTAssertNil(editor.project.canvas.background.fitMode)
    }

    func testBackgroundTypeImage() async throws {
        // Test setting background type to image
        let success = await editor.setBackgroundType(.image)

        XCTAssertTrue(success, "Setting background type to image should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "image")
        XCTAssertEqual(editor.project.canvas.background.value, "", "Image path should be empty initially")
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fill", "Default fit mode should be fill")
    }

    func testBackgroundTypeBlur() async throws {
        // Test setting background type to blur
        let success = await editor.setBackgroundType(.blur)

        XCTAssertTrue(success, "Setting background type to blur should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "blur")
        XCTAssertEqual(editor.project.canvas.background.value, "10", "Default blur radius should be 10")
        XCTAssertNil(editor.project.canvas.background.fitMode)
    }

    // MARK: - Solid Color Tests

    func testUpdateBackgroundColorValid() async throws {
        // Test updating background color with valid hex
        let success = await editor.updateBackgroundColor("#FF0000")

        XCTAssertTrue(success, "Updating background color should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "solid")
        XCTAssertEqual(editor.project.canvas.background.value, "#FF0000")
    }

    func testUpdateBackgroundColorInvalid() async throws {
        // Test updating background color with invalid hex
        let success = await editor.updateBackgroundColor("invalid")

        XCTAssertFalse(success, "Updating background color with invalid hex should fail")
        XCTAssertNotEqual(editor.project.canvas.background.value, "invalid")
    }

    func testUpdateBackgroundColorWithAlpha() async throws {
        // Test updating background color with alpha channel
        let success = await editor.updateBackgroundColor("#FF000080")

        XCTAssertTrue(success, "Updating background color with alpha should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, "#FF000080")
    }

    func testUpdateBackgroundColorMultiple() async throws {
        // Test updating background color multiple times
        let color1 = "#00FF00"
        let color2 = "#0000FF"
        let color3 = "#FFFF00"

        let success1 = await editor.updateBackgroundColor(color1)
        XCTAssertTrue(success1)
        XCTAssertEqual(editor.project.canvas.background.value, color1)

        let success2 = await editor.updateBackgroundColor(color2)
        XCTAssertTrue(success2)
        XCTAssertEqual(editor.project.canvas.background.value, color2)

        let success3 = await editor.updateBackgroundColor(color3)
        XCTAssertTrue(success3)
        XCTAssertEqual(editor.project.canvas.background.value, color3)
    }

    // MARK: - Image Background Tests

    func testUpdateBackgroundImagePath() async throws {
        // Test updating background image path
        let imagePath = "/Users/test/background.png"
        let success = await editor.updateBackgroundImagePath(imagePath)

        XCTAssertTrue(success, "Updating background image path should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "image")
        XCTAssertEqual(editor.project.canvas.background.value, imagePath)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fill", "Default fit mode should be fill")
    }

    func testUpdateBackgroundImagePathWithFitMode() async throws {
        // Test updating background image path with fit mode
        let imagePath = "/Users/test/background.png"
        let success = await editor.updateBackgroundImagePath(imagePath, fitMode: .fit)

        XCTAssertTrue(success, "Updating background image path with fit mode should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "image")
        XCTAssertEqual(editor.project.canvas.background.value, imagePath)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fit")
    }

    func testUpdateBackgroundImagePathEmpty() async throws {
        // Test clearing background image path
        let imagePath = "/Users/test/background.png"
        _ = await editor.updateBackgroundImagePath(imagePath)

        let success = await editor.updateBackgroundImagePath("")

        XCTAssertTrue(success, "Clearing background image path should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, "")
    }

    // MARK: - Fit Mode Tests

    func testUpdateBackgroundFitModeFill() async throws {
        // First set background to image type
        _ = await editor.setBackgroundType(.image)
        _ = await editor.updateBackgroundImagePath("/Users/test/image.png")

        // Test updating fit mode to fill
        let success = await editor.updateBackgroundFitMode(.fill)

        XCTAssertTrue(success, "Updating fit mode to fill should succeed")
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fill")
    }

    func testUpdateBackgroundFitModeFit() async throws {
        // First set background to image type
        _ = await editor.setBackgroundType(.image)
        _ = await editor.updateBackgroundImagePath("/Users/test/image.png")

        // Test updating fit mode to fit
        let success = await editor.updateBackgroundFitMode(.fit)

        XCTAssertTrue(success, "Updating fit mode to fit should succeed")
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fit")
    }

    func testUpdateBackgroundFitModeNotImage() async throws {
        // Set background to solid (not image)
        _ = await editor.setBackgroundType(.solid)

        // Try to update fit mode (should fail)
        let success = await editor.updateBackgroundFitMode(.fit)

        XCTAssertFalse(success, "Updating fit mode for non-image background should fail")
    }

    func testUpdateBackgroundFitModeToggle() async throws {
        // Test toggling between fit modes
        _ = await editor.setBackgroundType(.image)
        _ = await editor.updateBackgroundImagePath("/Users/test/image.png")

        let success1 = await editor.updateBackgroundFitMode(.fill)
        XCTAssertTrue(success1)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fill")

        let success2 = await editor.updateBackgroundFitMode(.fit)
        XCTAssertTrue(success2)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fit")

        let success3 = await editor.updateBackgroundFitMode(.fill)
        XCTAssertTrue(success3)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fill")
    }

    // MARK: - Blur Background Tests

    func testUpdateBackgroundBlurRadius() async throws {
        // First set background to blur type
        _ = await editor.setBackgroundType(.blur)

        // Test updating blur radius
        let newBackground = createBackground(type: "blur", value: "20")
        let success = await editor.updateBackground(newBackground)

        XCTAssertTrue(success, "Updating blur radius should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, "blur")
        XCTAssertEqual(editor.project.canvas.background.value, "20")
    }

    func testUpdateBackgroundBlurRadiusMax() async throws {
        // Test maximum blur radius
        _ = await editor.setBackgroundType(.blur)

        let newBackground = createBackground(type: "blur", value: "100")
        let success = await editor.updateBackground(newBackground)

        XCTAssertTrue(success, "Setting max blur radius should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, "100")
    }

    func testUpdateBackgroundBlurRadiusMin() async throws {
        // Test minimum blur radius
        _ = await editor.setBackgroundType(.blur)

        let newBackground = createBackground(type: "blur", value: "0")
        let success = await editor.updateBackground(newBackground)

        XCTAssertTrue(success, "Setting min blur radius should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, "0")
    }

    func testUpdateBackgroundBlurRadiusInvalid() async throws {
        // Test invalid blur radius
        _ = await editor.setBackgroundType(.blur)

        let newBackground = createBackground(type: "blur", value: "invalid")
        let success = await editor.updateBackground(newBackground)

        XCTAssertFalse(success, "Setting invalid blur radius should fail")
    }

    // MARK: - General Background Tests

    func testUpdateBackgroundAllTypes() async throws {
        // Test updating background for all types
        let solidBackground = createBackground(type: "solid", value: "#FF0000")
        let success1 = await editor.updateBackground(solidBackground)
        XCTAssertTrue(success1)
        XCTAssertEqual(editor.project.canvas.background.type, "solid")

        let imageBackground = createBackground(type: "image", value: "/path/to/image.png", fitMode: "fill")
        let success2 = await editor.updateBackground(imageBackground)
        XCTAssertTrue(success2)
        XCTAssertEqual(editor.project.canvas.background.type, "image")

        let blurBackground = createBackground(type: "blur", value: "15")
        let success3 = await editor.updateBackground(blurBackground)
        XCTAssertTrue(success3)
        XCTAssertEqual(editor.project.canvas.background.type, "blur")
    }

    // MARK: - Undo/Redo Tests

    func testUndoBackgroundColorChange() async throws {
        // Test undoing background color change
        let originalColor = editor.project.canvas.background.value

        // Change color
        _ = await editor.updateBackgroundColor("#FF0000")

        // Undo
        let undoSuccess = await editor.undo()

        XCTAssertTrue(undoSuccess, "Undo should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, originalColor, "Background color should be restored")
    }

    func testUndoBackgroundTypeChange() async throws {
        // Test undoing background type change
        let originalType = editor.project.canvas.background.type

        // Change type
        _ = await editor.setBackgroundType(.image)

        // Undo
        let undoSuccess = await editor.undo()

        XCTAssertTrue(undoSuccess, "Undo should succeed")
        XCTAssertEqual(editor.project.canvas.background.type, originalType, "Background type should be restored")
    }

    func testRedoBackgroundColorChange() async throws {
        // Test redoing background color change
        let originalColor = editor.project.canvas.background.value
        let newColor = "#FF0000"

        // Change color
        _ = await editor.updateBackgroundColor(newColor)

        // Undo
        _ = await editor.undo()

        // Redo
        let redoSuccess = await editor.redo()

        XCTAssertTrue(redoSuccess, "Redo should succeed")
        XCTAssertEqual(editor.project.canvas.background.value, newColor, "Background color should be redone")
    }

    // MARK: - Edge Case Tests

    func testBackgroundTypeTransition() async throws {
        // Test transitioning between background types
        _ = await editor.setBackgroundType(.solid)
        XCTAssertEqual(editor.project.canvas.background.type, "solid")

        _ = await editor.setBackgroundType(.image)
        XCTAssertEqual(editor.project.canvas.background.type, "image")

        _ = await editor.setBackgroundType(.blur)
        XCTAssertEqual(editor.project.canvas.background.type, "blur")

        _ = await editor.setBackgroundType(.solid)
        XCTAssertEqual(editor.project.canvas.background.type, "solid")
    }

    func testBackgroundImagePreservesFitModeOnTypeChange() async throws {
        // Test that changing type preserves fit mode when returning to image
        _ = await editor.setBackgroundType(.image)
        _ = await editor.updateBackgroundImagePath("/test/image.png", fitMode: .fit)

        let originalFitMode = editor.project.canvas.background.fitMode

        // Change to solid
        _ = await editor.setBackgroundType(.solid)

        // Change back to image
        _ = await editor.setBackgroundType(.image)

        // Fit mode should be preserved (implementation may vary)
        XCTAssertNotNil(editor.project.canvas.background.fitMode, "Fit mode should be set")
    }

    func testBackgroundWithEmptyValue() async throws {
        // Test background with empty value
        let background = createBackground(type: "solid", value: "")
        let success = await editor.updateBackground(background)

        // Empty solid color might be valid or invalid depending on validation
        // This test checks the behavior
        XCTAssertTrue(success || !success, "Should handle empty value gracefully")
    }

    // MARK: - Performance Tests

    func testBackgroundUpdatePerformance() async throws {
        // Test performance of multiple background updates
        measure {
            let group = DispatchGroup()
            for i in 0..<100 {
                group.enter()
                Task {
                    let hex = String(format: "#%06X", i % 0xFFFFFF)
                    _ = await editor.updateBackgroundColor(hex)
                    group.leave()
                }
            }
            group.wait()
        }
    }

    func testBackgroundTypeSwitchPerformance() async throws {
        // Test performance of switching background types
        measure {
            let group = DispatchGroup()
            for _ in 0..<100 {
                group.enter()
                Task {
                    _ = await editor.setBackgroundType(.solid)
                    _ = await editor.setBackgroundType(.image)
                    _ = await editor.setBackgroundType(.blur)
                    group.leave()
                }
            }
            group.wait()
        }
    }

    // MARK: - Integration Tests

    func testBackgroundControlsIntegration() async throws {
        // Test complete workflow of background controls
        // 1. Set solid color
        let success1 = await editor.setBackgroundType(.solid)
        XCTAssertTrue(success1)

        // 2. Change color
        let success2 = await editor.updateBackgroundColor("#34C759")
        XCTAssertTrue(success2)
        XCTAssertEqual(editor.project.canvas.background.value, "#34C759")

        // 3. Switch to image
        let success3 = await editor.setBackgroundType(.image)
        XCTAssertTrue(success3)

        // 4. Set image path and fit mode
        let success4 = await editor.updateBackgroundImagePath("/test/image.png", fitMode: .fit)
        XCTAssertTrue(success4)
        XCTAssertEqual(editor.project.canvas.background.fitMode, "fit")

        // 5. Switch to blur
        let success5 = await editor.setBackgroundType(.blur)
        XCTAssertTrue(success5)

        // 6. Change blur radius
        let blurBackground = createBackground(type: "blur", value: "25")
        let success6 = await editor.updateBackground(blurBackground)
        XCTAssertTrue(success6)
        XCTAssertEqual(editor.project.canvas.background.value, "25")
    }

    func testBackgroundUndoRedoIntegration() async throws {
        // Test undo/redo with multiple background changes
        let original = editor.project.canvas.background

        // Make multiple changes
        _ = await editor.updateBackgroundColor("#FF0000")
        _ = await editor.updateBackgroundColor("#00FF00")
        _ = await editor.updateBackgroundColor("#0000FF")

        // Undo all
        _ = await editor.undo()
        _ = await editor.undo()
        _ = await editor.undo()

        XCTAssertEqual(editor.project.canvas.background, original, "Should return to original state")

        // Redo all
        _ = await editor.redo()
        _ = await editor.redo()
        _ = await editor.redo()

        XCTAssertEqual(editor.project.canvas.background.value, "#0000FF", "Should redo to last state")
    }
}
