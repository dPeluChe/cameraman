//
//  CaptureGeometryTests.swift
//  EngineKitTests
//
//  Coordinate-space mapping between cursor telemetry (global Cocoa points)
//  and recorded video space.
//

import XCTest
@testable import EngineKit

final class CaptureGeometryTests: XCTestCase {

    // MARK: - normalized()

    func testNormalizedFullDisplayAtOrigin() {
        // Full 1920×1080-point display at origin (e.g. Retina main display —
        // scale plays no role because both spaces are points).
        let geometry = CaptureGeometry(
            rect: .init(x: 0, y: 0, w: 1920, h: 1080),
            scale: 2.0
        )

        let center = geometry.normalized(x: 960, y: 540)
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)

        let bottomLeft = geometry.normalized(x: 0, y: 0)
        XCTAssertEqual(bottomLeft.x, 0)
        XCTAssertEqual(bottomLeft.y, 0)

        let topRight = geometry.normalized(x: 1920, y: 1080)
        XCTAssertEqual(topRight.x, 1)
        XCTAssertEqual(topRight.y, 1)
    }

    func testNormalizedOffsetRegion() {
        // Area recording / secondary display: capture rect offset from the
        // global origin — the offset must be subtracted before normalizing.
        let geometry = CaptureGeometry(
            rect: .init(x: 100, y: 200, w: 800, h: 600),
            scale: 2.0
        )

        let center = geometry.normalized(x: 500, y: 500)
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testNormalizedClampsOutOfRegion() {
        let geometry = CaptureGeometry(
            rect: .init(x: 100, y: 100, w: 500, h: 500),
            scale: 1.0
        )

        let outside = geometry.normalized(x: 0, y: 9999)
        XCTAssertEqual(outside.x, 0)
        XCTAssertEqual(outside.y, 1)
    }

    func testNormalizedDegenerateRect() {
        let geometry = CaptureGeometry(rect: .init(x: 0, y: 0, w: 0, h: 0), scale: 1.0)
        let result = geometry.normalized(x: 100, y: 100)
        XCTAssertEqual(result.x, 0)
        XCTAssertEqual(result.y, 0)
    }

    // MARK: - rebaseToCaptureSpace()

    func testRebaseOffsetsAndFilters() {
        let geometry = CaptureGeometry(
            rect: .init(x: 100, y: 200, w: 800, h: 600),
            scale: 2.0
        )

        let events = [
            TelemetryRecorder.Event(t: 1.0, type: .move, x: 500, y: 500),
            TelemetryRecorder.Event(t: 2.0, type: .down, x: 100, y: 200, button: 0),
            // Outside the capture region — must be dropped, not clamped
            TelemetryRecorder.Event(t: 3.0, type: .down, x: 50, y: 500, button: 0),
            TelemetryRecorder.Event(t: 4.0, type: .move, x: 2000, y: 500)
        ]

        let rebased = geometry.rebaseToCaptureSpace(events)

        XCTAssertEqual(rebased.count, 2)
        XCTAssertEqual(rebased[0].x, 400)
        XCTAssertEqual(rebased[0].y, 300)
        XCTAssertEqual(rebased[1].x, 0)
        XCTAssertEqual(rebased[1].y, 0)
    }

    func testRebasePreservesEventMetadata() {
        let geometry = CaptureGeometry(rect: .init(x: 10, y: 10, w: 100, h: 100), scale: 1.0)
        let event = TelemetryRecorder.Event(
            t: 5.5, type: .scroll, x: 50, y: 60, button: 1, dx: 1.5, dy: -2.5, displayID: "main"
        )

        let rebased = geometry.rebaseToCaptureSpace([event])

        XCTAssertEqual(rebased.count, 1)
        XCTAssertEqual(rebased[0].t, 5.5)
        XCTAssertEqual(rebased[0].type, .scroll)
        XCTAssertEqual(rebased[0].button, 1)
        XCTAssertEqual(rebased[0].dx, 1.5)
        XCTAssertEqual(rebased[0].dy, -2.5)
        XCTAssertEqual(rebased[0].displayID, "main")
    }

    // MARK: - rect(fromLocalTopLeft:inDisplayFrame:)

    func testTopLeftRectConversionOnMainDisplay() {
        // Main display: frame origin (0,0), 1920×1080 points.
        // A selection 100pt from the left, 50pt from the TOP, 800×600.
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let local = CGRect(x: 100, y: 50, width: 800, height: 600)

        let rect = CaptureGeometry.rect(fromLocalTopLeft: local, inDisplayFrame: frame)

        XCTAssertEqual(rect.x, 100)
        // Bottom edge: 1080 - (50 + 600) = 430 in Cocoa (bottom-left) coords
        XCTAssertEqual(rect.y, 430)
        XCTAssertEqual(rect.w, 800)
        XCTAssertEqual(rect.h, 600)
    }

    func testTopLeftRectConversionOnSecondaryDisplay() {
        // Secondary display to the right of main, slightly raised.
        let frame = CGRect(x: 1920, y: 200, width: 1440, height: 900)
        let local = CGRect(x: 40, y: 100, width: 400, height: 300)

        let rect = CaptureGeometry.rect(fromLocalTopLeft: local, inDisplayFrame: frame)

        XCTAssertEqual(rect.x, 1960)
        // frame.maxY (1100) - local.maxY (400) = 700
        XCTAssertEqual(rect.y, 700)
        XCTAssertEqual(rect.w, 400)
        XCTAssertEqual(rect.h, 300)
    }

    // MARK: - Schema backward compatibility

    func testMediaTrackDecodesWithoutCaptureKey() throws {
        // Pre-geometry project.json — the capture key is absent.
        let json = """
        {"path": "sources/screen.mov", "fps": 60, "size": {"w": 3840, "h": 2160},
         "syncOffsetMs": 0, "sha256": "", "sizeBytes": 0}
        """
        let track = try JSONDecoder().decode(
            Project.Sources.MediaTrack.self, from: Data(json.utf8)
        )
        XCTAssertNil(track.capture)
    }

    func testMediaTrackCaptureRoundTrip() throws {
        let track = Project.Sources.MediaTrack(
            path: "sources/screen.mov",
            fps: 60,
            size: .init(w: 3840, h: 2160),
            capture: CaptureGeometry(rect: .init(x: 0, y: 0, w: 1920, h: 1080), scale: 2.0)
        )

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Project.Sources.MediaTrack.self, from: data)

        XCTAssertEqual(decoded.capture, track.capture)
        XCTAssertEqual(decoded.capture?.scale, 2.0)
        XCTAssertEqual(decoded.capture?.rect.w, 1920)
    }

    // MARK: - End-to-end: retina focus points

    func testRetinaFocusNoLongerCollapsesToLowerQuadrant() {
        // The original bug: telemetry points (0–1920) divided by pixel dims
        // (0–3840) pushed every focus ≤ 0.5. With geometry, a click at the
        // top-right of a 2× display must normalize near (1, 1).
        let geometry = CaptureGeometry(
            rect: .init(x: 0, y: 0, w: 1920, h: 1080),
            scale: 2.0
        )

        let focus = geometry.normalized(x: 1900, y: 1060)
        XCTAssertGreaterThan(focus.x, 0.95)
        XCTAssertGreaterThan(focus.y, 0.95)
    }
}
