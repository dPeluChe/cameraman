//
//  PiPLayoutHelperTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-24.
//

import XCTest
@testable import App
@testable import EngineKit

final class PiPLayoutHelperTests: XCTestCase {
    func testMovedCameraClampsToBounds() {
        let camera = Project.Canvas.Layout.CameraPosition(x: 0.8, y: 0.1, w: 0.25, h: 0.25, cornerRadius: 8)
        let moved = PiPLayoutHelper.moved(camera: camera, deltaX: 0.2, deltaY: -0.2)

        XCTAssertEqual(moved.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.0, accuracy: 0.0001)
    }

    func testResizedTopLeftHonorsMinimumSize() {
        let camera = Project.Canvas.Layout.CameraPosition(x: 0.1, y: 0.1, w: 0.2, h: 0.2, cornerRadius: 8)
        let resized = PiPLayoutHelper.resized(camera: camera, handle: .topLeft, deltaX: 0.2, deltaY: 0.2, minimumSize: 0.12)

        XCTAssertEqual(resized.x, 0.18, accuracy: 0.0001)
        XCTAssertEqual(resized.y, 0.18, accuracy: 0.0001)
        XCTAssertEqual(resized.w, 0.12, accuracy: 0.0001)
        XCTAssertEqual(resized.h, 0.12, accuracy: 0.0001)
    }

    func testResizedBottomRightClampsToCanvas() {
        let camera = Project.Canvas.Layout.CameraPosition(x: 0.7, y: 0.7, w: 0.2, h: 0.2, cornerRadius: 8)
        let resized = PiPLayoutHelper.resized(camera: camera, handle: .bottomRight, deltaX: 0.2, deltaY: 0.2)

        XCTAssertEqual(resized.w, 0.3, accuracy: 0.0001)
        XCTAssertEqual(resized.h, 0.3, accuracy: 0.0001)
    }

    func testPresetPositionsRespectMargin() {
        let camera = Project.Canvas.Layout.CameraPosition(x: 0.2, y: 0.2, w: 0.2, h: 0.2, cornerRadius: 8)
        let preset = PiPLayoutHelper.presetPosition(.topRight, camera: camera, margin: 0.05)

        XCTAssertEqual(preset.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(preset.y, 0.05, accuracy: 0.0001)
    }
}
