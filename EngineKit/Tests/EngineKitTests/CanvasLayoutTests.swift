//
//  CanvasLayoutTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for CanvasLayout functionality
final class CanvasLayoutTests: XCTestCase {

    // MARK: - Layout Preset Tests

    func testLayoutPresetDisplayNames() {
        XCTAssertEqual(CanvasLayout.LayoutPreset.pip.displayName, "Picture-in-Picture")
        XCTAssertEqual(CanvasLayout.LayoutPreset.sideBySide.displayName, "Side-by-Side")
        XCTAssertEqual(CanvasLayout.LayoutPreset.fullscreen.displayName, "Fullscreen")
        XCTAssertEqual(CanvasLayout.LayoutPreset.cinematic.displayName, "Cinematic")
    }

    func testLayoutPresetDescriptions() {
        XCTAssertFalse(CanvasLayout.LayoutPreset.pip.description.isEmpty)
        XCTAssertFalse(CanvasLayout.LayoutPreset.sideBySide.description.isEmpty)
        XCTAssertFalse(CanvasLayout.LayoutPreset.fullscreen.description.isEmpty)
        XCTAssertFalse(CanvasLayout.LayoutPreset.cinematic.description.isEmpty)
    }

    func testLayoutPresetRawValues() {
        XCTAssertEqual(CanvasLayout.LayoutPreset.pip.rawValue, "pip")
        XCTAssertEqual(CanvasLayout.LayoutPreset.sideBySide.rawValue, "side-by-side")
        XCTAssertEqual(CanvasLayout.LayoutPreset.fullscreen.rawValue, "fullscreen")
        XCTAssertEqual(CanvasLayout.LayoutPreset.cinematic.rawValue, "cinematic")
    }

    func testDefaultLayoutForPreset() {
        // Test PiP layout
        let pipLayout = CanvasLayout.defaultLayout(for: .pip)
        XCTAssertEqual(pipLayout.type, "pip")
        XCTAssertNotNil(pipLayout.camera)
        XCTAssertEqual(pipLayout.camera!.x, 0.74, accuracy: 0.001)
        XCTAssertEqual(pipLayout.camera!.y, 0.72, accuracy: 0.001)
        XCTAssertEqual(pipLayout.camera!.w, 0.22, accuracy: 0.001)
        XCTAssertEqual(pipLayout.camera!.h, 0.22, accuracy: 0.001)
        XCTAssertEqual(pipLayout.camera!.cornerRadius, 18, accuracy: 0.001)

        // Test side-by-side layout
        let sbsLayout = CanvasLayout.defaultLayout(for: .sideBySide)
        XCTAssertEqual(sbsLayout.type, "side-by-side")
        XCTAssertNotNil(sbsLayout.camera)
        XCTAssertEqual(sbsLayout.camera!.x, 0.51, accuracy: 0.001)
        XCTAssertEqual(sbsLayout.camera!.y, 0.25, accuracy: 0.001)
        XCTAssertEqual(sbsLayout.camera!.w, 0.47, accuracy: 0.001)
        XCTAssertEqual(sbsLayout.camera!.h, 0.5, accuracy: 0.001)
        XCTAssertEqual(sbsLayout.camera!.cornerRadius, 12, accuracy: 0.001)

        // Test fullscreen layout
        let fsLayout = CanvasLayout.defaultLayout(for: .fullscreen)
        XCTAssertEqual(fsLayout.type, "fullscreen")
        XCTAssertNil(fsLayout.camera)

        // Test cinematic layout
        let cinematicLayout = CanvasLayout.defaultLayout(for: .cinematic)
        XCTAssertEqual(cinematicLayout.type, "cinematic")
        XCTAssertNotNil(cinematicLayout.camera)
        XCTAssertEqual(cinematicLayout.camera!.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(cinematicLayout.camera!.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(cinematicLayout.camera!.w, 0.9, accuracy: 0.001)
        XCTAssertEqual(cinematicLayout.camera!.h, 0.6, accuracy: 0.001)
        XCTAssertEqual(cinematicLayout.camera!.cornerRadius, 24, accuracy: 0.001)
    }

    // MARK: - Aspect Ratio Tests

    func testAspectRatioDisplayNames() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.displayName, "16:9")
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.displayName, "9:16")
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.displayName, "1:1")
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.displayName, "4:3")
    }

    func testAspectRatioWidthCalculation() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.width(for: 1080), 1920)
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.width(for: 1080), 607)
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.width(for: 1080), 1080)
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.width(for: 1080), 1440)
    }

    func testAspectRatioHeightCalculation() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.height(for: 1920), 1080)
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.height(for: 1920), 3402)
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.height(for: 1920), 1920)
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.height(for: 1920), 1440)
    }

    func testAspectRatioRawValues() {
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape16_9.rawValue, "16:9")
        XCTAssertEqual(CanvasLayout.AspectRatio.portrait9_16.rawValue, "9:16")
        XCTAssertEqual(CanvasLayout.AspectRatio.square1_1.rawValue, "1:1")
        XCTAssertEqual(CanvasLayout.AspectRatio.landscape4_3.rawValue, "4:3")
    }

    // MARK: - Background Type Tests

    func testBackgroundTypeDisplayNames() {
        XCTAssertEqual(CanvasLayout.BackgroundType.solid.displayName, "Solid Color")
        XCTAssertEqual(CanvasLayout.BackgroundType.image.displayName, "Image")
        XCTAssertEqual(CanvasLayout.BackgroundType.blur.displayName, "Blurred Screen")
    }

    func testDefaultBackgroundForType() {
        // Test solid background
        let solidBg = CanvasLayout.defaultBackground(for: .solid)
        XCTAssertEqual(solidBg.type, "solid")
        XCTAssertEqual(solidBg.value, "#0B0B0D")

        // Test image background
        let imageBg = CanvasLayout.defaultBackground(for: .image)
        XCTAssertEqual(imageBg.type, "image")
        XCTAssertEqual(imageBg.value, "") // Empty path

        // Test blur background
        let blurBg = CanvasLayout.defaultBackground(for: .blur)
        XCTAssertEqual(blurBg.type, "blur")
        XCTAssertEqual(blurBg.value, "10") // Default blur radius
    }

    // MARK: - Frame Calculation Tests

    func testCalculateCameraFrame() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.5,
                y: 0.5,
                w: 0.25,
                h: 0.25,
                cornerRadius: 10
            )
        )

        let frame = CanvasLayout.calculateCameraFrame(
            layout: layout,
            canvasWidth: 1920,
            canvasHeight: 1080
        )

        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.x, 960, accuracy: 0.1) // 0.5 * 1920
        XCTAssertEqual(frame!.y, 540, accuracy: 0.1) // 0.5 * 1080
        XCTAssertEqual(frame!.width, 480, accuracy: 0.1) // 0.25 * 1920
        XCTAssertEqual(frame!.height, 270, accuracy: 0.1) // 0.25 * 1080
    }

    func testCalculateCameraFrameNil() {
        let layout = Project.Canvas.Layout(
            type: "fullscreen",
            camera: nil
        )

        let frame = CanvasLayout.calculateCameraFrame(
            layout: layout,
            canvasWidth: 1920,
            canvasHeight: 1080
        )

        XCTAssertNil(frame)
    }

    func testCalculateScreenFrameForPip() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: 18
            )
        )

        let frame = CanvasLayout.calculateScreenFrame(
            layout: layout,
            canvasWidth: 1920,
            canvasHeight: 1080
        )

        XCTAssertEqual(frame.x, 0)
        XCTAssertEqual(frame.y, 0)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
    }

    func testCalculateScreenFrameForSideBySide() {
        let layout = Project.Canvas.Layout(
            type: "side-by-side",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.51,
                y: 0.25,
                w: 0.47,
                h: 0.5,
                cornerRadius: 12
            )
        )

        let frame = CanvasLayout.calculateScreenFrame(
            layout: layout,
            canvasWidth: 1920,
            canvasHeight: 1080
        )

        XCTAssertEqual(frame.x, 10, accuracy: 0.1) // Padding
        XCTAssertEqual(frame.y, 10, accuracy: 0.1) // Padding
        XCTAssertEqual(frame.width, 940.8, accuracy: 0.1) // 49% of 1920
        XCTAssertEqual(frame.height, 1060, accuracy: 0.1) // 1080 - 2*padding
    }

    func testCalculateScreenFrameForFullscreen() {
        let layout = Project.Canvas.Layout(
            type: "fullscreen",
            camera: nil
        )

        let frame = CanvasLayout.calculateScreenFrame(
            layout: layout,
            canvasWidth: 1920,
            canvasHeight: 1080
        )

        XCTAssertEqual(frame.x, 0)
        XCTAssertEqual(frame.y, 0)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
    }

    // MARK: - Validation Tests

    func testValidateLayoutSuccess() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: 18
            )
        )

        XCTAssertNoThrow(try CanvasLayout.validateLayout(layout, hasCamera: true))
    }

    func testValidateLayoutInvalidType() {
        let layout = Project.Canvas.Layout(
            type: "invalid-type",
            camera: nil
        )

        XCTAssertThrowsError(try CanvasLayout.validateLayout(layout, hasCamera: false)) { error in
            if case .invalidLayoutPreset(let type) = error as? CanvasLayout.LayoutError {
                XCTAssertEqual(type, "invalid-type")
            } else {
                XCTFail("Expected invalidLayoutPreset error")
            }
        }
    }

    func testValidateLayoutCameraPositionOutOfBounds() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 1.5, // Out of bounds
                y: 0.5,
                w: 0.22,
                h: 0.22,
                cornerRadius: 18
            )
        )

        XCTAssertThrowsError(try CanvasLayout.validateLayout(layout, hasCamera: true)) { error in
            if case .invalidCameraPosition(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("x must be between 0 and 1"))
            } else {
                XCTFail("Expected invalidCameraPosition error")
            }
        }
    }

    func testValidateLayoutCameraFrameExceedsBounds() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.8,
                y: 0.8,
                w: 0.3, // Will exceed bounds (0.8 + 0.3 = 1.1 > 1.0)
                h: 0.2,
                cornerRadius: 18
            )
        )

        XCTAssertThrowsError(try CanvasLayout.validateLayout(layout, hasCamera: true)) { error in
            if case .invalidCameraPosition(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("exceeds canvas width"))
            } else {
                XCTFail("Expected invalidCameraPosition error")
            }
        }
    }

    func testValidateLayoutNegativeCornerRadius() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: -10 // Negative
            )
        )

        XCTAssertThrowsError(try CanvasLayout.validateLayout(layout, hasCamera: true)) { error in
            if case .invalidCameraPosition(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("cornerRadius must be non-negative"))
            } else {
                XCTFail("Expected invalidCameraPosition error")
            }
        }
    }

    func testValidateBackgroundSolidValid() {
        let background = Project.Canvas.Background(type: "solid", value: "#0B0B0D")
        XCTAssertNoThrow(try CanvasLayout.validateBackground(background))
    }

    func testValidateBackgroundSolidInvalidHex() {
        let background = Project.Canvas.Background(type: "solid", value: "invalid-color")
        XCTAssertThrowsError(try CanvasLayout.validateBackground(background)) { error in
            if case .invalidBackgroundValue(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("Invalid hex color format"))
            } else {
                XCTFail("Expected invalidBackgroundValue error")
            }
        }
    }

    func testValidateBackgroundBlurValid() {
        let background = Project.Canvas.Background(type: "blur", value: "10")
        XCTAssertNoThrow(try CanvasLayout.validateBackground(background))
    }

    func testValidateBackgroundBlurOutOfRange() {
        let background = Project.Canvas.Background(type: "blur", value: "150") // > 100
        XCTAssertThrowsError(try CanvasLayout.validateBackground(background)) { error in
            if case .invalidBackgroundValue(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("Blur radius must be between 0 and 100"))
            } else {
                XCTFail("Expected invalidBackgroundValue error")
            }
        }
    }

    func testValidateBackgroundInvalidType() {
        let background = Project.Canvas.Background(type: "invalid-type", value: "something")
        XCTAssertThrowsError(try CanvasLayout.validateBackground(background)) { error in
            if case .invalidBackgroundValue(let value) = error as? CanvasLayout.LayoutError {
                XCTAssertEqual(value, "invalid-type")
            } else {
                XCTFail("Expected invalidBackgroundValue error")
            }
        }
    }

    func testValidateFormatSuccess() {
        let format = Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080)
        XCTAssertNoThrow(try CanvasLayout.validateFormat(format))
    }

    func testValidateFormatInvalidAspectRatio() {
        let format = Project.Canvas.Format(aspect: "invalid-ratio", w: 1920, h: 1080)
        XCTAssertThrowsError(try CanvasLayout.validateFormat(format)) { error in
            if case .invalidAspectRatio(let aspect) = error as? CanvasLayout.LayoutError {
                XCTAssertEqual(aspect, "invalid-ratio")
            } else {
                XCTFail("Expected invalidAspectRatio error")
            }
        }
    }

    func testValidateFormatDimensionMismatch() {
        let format = Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1000) // Not 16:9
        XCTAssertThrowsError(try CanvasLayout.validateFormat(format)) { error in
            if case .invalidAspectRatio(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("don't match aspect ratio"))
            } else {
                XCTFail("Expected invalidAspectRatio error")
            }
        }
    }

    func testValidateFormatZeroDimensions() {
        let format1 = Project.Canvas.Format(aspect: "16:9", w: 0, h: 1080)
        XCTAssertThrowsError(try CanvasLayout.validateFormat(format1)) { error in
            if case .invalidAspectRatio(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("Width must be positive"))
            } else {
                XCTFail("Expected invalidAspectRatio error")
            }
        }

        let format2 = Project.Canvas.Format(aspect: "16:9", w: 1920, h: 0)
        XCTAssertThrowsError(try CanvasLayout.validateFormat(format2)) { error in
            if case .invalidAspectRatio(let reason) = error as? CanvasLayout.LayoutError {
                XCTAssertTrue(reason.contains("Height must be positive"))
            } else {
                XCTFail("Expected invalidAspectRatio error")
            }
        }
    }

    // MARK: - Format Creation Tests

    func testCreateFormatFor16_9() {
        let format = CanvasLayout.createFormat(for: .landscape16_9, baseWidth: 1920)
        XCTAssertEqual(format.aspect, "16:9")
        XCTAssertEqual(format.w, 1920)
        XCTAssertEqual(format.h, 1080)
    }

    func testCreateFormatFor9_16() {
        let format = CanvasLayout.createFormat(for: .portrait9_16)
        XCTAssertEqual(format.aspect, "9:16")
        XCTAssertEqual(format.w, 607)
        XCTAssertEqual(format.h, 3402)
    }

    func testCreateFormatFor1_1() {
        let format = CanvasLayout.createFormat(for: .square1_1)
        XCTAssertEqual(format.aspect, "1:1")
        XCTAssertEqual(format.w, 1080)
        XCTAssertEqual(format.h, 1080)
    }

    func testCreateFormatFor4_3() {
        let format = CanvasLayout.createFormat(for: .landscape4_3)
        XCTAssertEqual(format.aspect, "4:3")
        XCTAssertEqual(format.w, 1440)
        XCTAssertEqual(format.h, 1080)
    }

    // MARK: - Layout Compatibility Tests

    func testRecommendedLayoutsForAspectRatio() {
        let landscapeLayouts = CanvasLayout.recommendedLayouts(for: .landscape16_9)
        XCTAssertTrue(landscapeLayouts.contains(.pip))
        XCTAssertTrue(landscapeLayouts.contains(.sideBySide))
        XCTAssertTrue(landscapeLayouts.contains(.fullscreen))
        XCTAssertTrue(landscapeLayouts.contains(.cinematic))

        let portraitLayouts = CanvasLayout.recommendedLayouts(for: .portrait9_16)
        XCTAssertTrue(portraitLayouts.contains(.pip))
        XCTAssertTrue(portraitLayouts.contains(.fullscreen))
        XCTAssertFalse(portraitLayouts.contains(.sideBySide)) // Not recommended for portrait
    }

    func testIsLayoutCompatible() {
        // Landscape compatibility
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .pip, aspectRatio: .landscape16_9))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .sideBySide, aspectRatio: .landscape16_9))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .fullscreen, aspectRatio: .landscape16_9))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .cinematic, aspectRatio: .landscape16_9))

        // Portrait compatibility
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .pip, aspectRatio: .portrait9_16))
        XCTAssertFalse(CanvasLayout.isLayoutCompatible(layout: .sideBySide, aspectRatio: .portrait9_16))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .fullscreen, aspectRatio: .portrait9_16))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .cinematic, aspectRatio: .portrait9_16))

        // Square compatibility
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .pip, aspectRatio: .square1_1))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .sideBySide, aspectRatio: .square1_1))
        XCTAssertTrue(CanvasLayout.isLayoutCompatible(layout: .fullscreen, aspectRatio: .square1_1))
    }

    // MARK: - Camera Position Adjustment Tests

    func testAdjustCameraPositionLandscapeToPortrait() {
        let originalCamera = Project.Canvas.Layout.CameraPosition(
            x: 0.74,
            y: 0.72,
            w: 0.22,
            h: 0.22,
            cornerRadius: 18
        )

        let adjusted = CanvasLayout.adjustCameraPosition(
            originalCamera,
            from: .landscape16_9,
            to: .portrait9_16
        )

        // Should be centered horizontally and moved to bottom
        XCTAssertEqual(adjusted.x, 0.5 - (0.22 / 2), accuracy: 0.001)
        XCTAssertEqual(adjusted.y, 0.75, accuracy: 0.001)
        XCTAssertEqual(adjusted.w, 0.22, accuracy: 0.001)
        XCTAssertEqual(adjusted.h, 0.22, accuracy: 0.001)
        XCTAssertEqual(adjusted.cornerRadius, 18, accuracy: 0.001)
    }

    func testAdjustCameraPositionPortraitToLandscape() {
        let originalCamera = Project.Canvas.Layout.CameraPosition(
            x: 0.3,
            y: 0.75,
            w: 0.5,
            h: 0.2,
            cornerRadius: 12
        )

        let adjusted = CanvasLayout.adjustCameraPosition(
            originalCamera,
            from: .portrait9_16,
            to: .landscape16_9
        )

        // Should restore to default PiP position
        XCTAssertEqual(adjusted.x, 0.74, accuracy: 0.001)
        XCTAssertEqual(adjusted.y, 0.72, accuracy: 0.001)
        XCTAssertEqual(adjusted.w, 0.22, accuracy: 0.001)
        XCTAssertEqual(adjusted.h, 0.22, accuracy: 0.001)
        XCTAssertEqual(adjusted.cornerRadius, 12, accuracy: 0.001)
    }

    func testAdjustCameraPositionSameAspectRatio() {
        let originalCamera = Project.Canvas.Layout.CameraPosition(
            x: 0.5,
            y: 0.5,
            w: 0.3,
            h: 0.3,
            cornerRadius: 15
        )

        let adjusted = CanvasLayout.adjustCameraPosition(
            originalCamera,
            from: .landscape16_9,
            to: .landscape16_9
        )

        // Should remain unchanged
        XCTAssertEqual(adjusted.x, originalCamera.x, accuracy: 0.001)
        XCTAssertEqual(adjusted.y, originalCamera.y, accuracy: 0.001)
        XCTAssertEqual(adjusted.w, originalCamera.w, accuracy: 0.001)
        XCTAssertEqual(adjusted.h, originalCamera.h, accuracy: 0.001)
        XCTAssertEqual(adjusted.cornerRadius, originalCamera.cornerRadius, accuracy: 0.001)
    }

    // MARK: - Error Description Tests

    func testLayoutErrorDescriptions() {
        let errors: [CanvasLayout.LayoutError] = [
            .invalidAspectRatio("16:9"),
            .invalidLayoutPreset("pip"),
            .invalidCameraPosition("out of bounds"),
            .missingCameraTrack,
            .invalidBackgroundValue("#FFFFFF")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Performance Tests

    func testFrameCalculationPerformance() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: 18
            )
        )

        measure {
            for _ in 0..<1000 {
                _ = CanvasLayout.calculateCameraFrame(layout: layout, canvasWidth: 1920, canvasHeight: 1080)
                _ = CanvasLayout.calculateScreenFrame(layout: layout, canvasWidth: 1920, canvasHeight: 1080)
            }
        }
    }

    func testValidationPerformance() {
        let layout = Project.Canvas.Layout(
            type: "pip",
            camera: Project.Canvas.Layout.CameraPosition(
                x: 0.74,
                y: 0.72,
                w: 0.22,
                h: 0.22,
                cornerRadius: 18
            )
        )

        let background = Project.Canvas.Background(type: "solid", value: "#0B0B0D")
        let format = Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080)

        measure {
            for _ in 0..<1000 {
                try? CanvasLayout.validateLayout(layout, hasCamera: true)
                try? CanvasLayout.validateBackground(background)
                try? CanvasLayout.validateFormat(format)
            }
        }
    }
}
