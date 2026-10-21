import XCTest
import AppKit
import EngineKit
@testable import Cameraman

@MainActor
final class LiveAnnotationRendererTests: XCTestCase {
    private let size = CGSize(width: 200, height: 100)

    /// Renders into a top-left-origin bitmap and returns a pixel probe.
    private func render(_ annotation: LiveAnnotation) throws -> (CGPoint) -> NSColor {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        ctx.cgContext.translateBy(x: 0, y: size.height)
        ctx.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        LiveAnnotationRenderer.draw(annotation, in: size)
        NSGraphicsContext.restoreGraphicsState()
        return { p in rep.colorAt(x: Int(p.x), y: Int(p.y)) ?? .clear }
    }

    private func shape(_ kind: LiveAnnotation.Kind, _ points: [CGPoint], text: String? = nil) -> LiveAnnotation {
        LiveAnnotation(kind: kind, points: points, colorHex: "#FF0000", lineWidth: 6, text: text, start: 0)
    }

    func testRectangleDrawsItsEdgeAndLeavesTheInsideClear() throws {
        let probe = try render(shape(.rect, [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8)]))
        XCTAssertGreaterThan(probe(CGPoint(x: 40, y: 50)).alphaComponent, 0.9, "left edge")
        XCTAssertEqual(probe(CGPoint(x: 100, y: 50)).alphaComponent, 0, accuracy: 0.01, "inside stays transparent")
        XCTAssertEqual(probe(CGPoint(x: 5, y: 5)).alphaComponent, 0, accuracy: 0.01, "outside stays transparent")
    }

    func testArrowRunsFromTailToHeadWithAHeadAtTheTip() throws {
        let probe = try render(shape(.arrow, [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)]))
        XCTAssertGreaterThan(probe(CGPoint(x: 60, y: 50)).alphaComponent, 0.9, "shaft")
        XCTAssertGreaterThan(probe(CGPoint(x: 176, y: 50)).alphaComponent, 0.9, "head just behind the tip")
        // The head is wider than the shaft: a pixel off the shaft but inside the head is painted.
        XCTAssertGreaterThan(probe(CGPoint(x: 164, y: 56)).alphaComponent, 0.9, "head wing")
        XCTAssertEqual(probe(CGPoint(x: 60, y: 62)).alphaComponent, 0, accuracy: 0.01, "off the shaft")
        XCTAssertEqual(probe(CGPoint(x: 24, y: 50)).redComponent, 1, accuracy: 0.05)
    }

    func testEllipseDoesNotPaintItsBoundingBoxCorner() throws {
        let probe = try render(shape(.ellipse, [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)]))
        XCTAssertGreaterThan(probe(CGPoint(x: 100, y: 10)).alphaComponent, 0.9, "top of the ellipse")
        XCTAssertEqual(probe(CGPoint(x: 22, y: 12)).alphaComponent, 0, accuracy: 0.01, "corner of the box")
    }

    func testPenFollowsItsPoints() throws {
        let probe = try render(shape(.pen, [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.9, y: 0.1)]))
        XCTAssertGreaterThan(probe(CGPoint(x: 100, y: 90)).alphaComponent, 0.9, "the V's bottom")
        XCTAssertEqual(probe(CGPoint(x: 100, y: 10)).alphaComponent, 0, accuracy: 0.01)
    }

    func testTextPaintsSomethingNearItsAnchor() throws {
        let probe = try render(shape(.text, [CGPoint(x: 0.1, y: 0.3)], text: "HOLA"))
        let painted = (20..<80).flatMap { x in (30..<60).map { CGPoint(x: x, y: $0) } }.contains { probe($0).alphaComponent > 0.5 }
        XCTAssertTrue(painted)
    }
}

final class RecordingClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testElapsedBeforeStartIsZero() {
        XCTAssertEqual(RecordingClock().elapsed(now: t0), 0)
    }

    func testPausedTimeIsSkipped() {
        var clock = RecordingClock(start: t0)
        clock.pause(now: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(14)), 10, accuracy: 0.001, "frozen while paused")
        clock.resume(now: t0.addingTimeInterval(20))
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(25)), 15, accuracy: 0.001)
    }

    func testDoublePauseAndResumeAreHarmless() {
        var clock = RecordingClock(start: t0)
        clock.resume(now: t0.addingTimeInterval(1))
        clock.pause(now: t0.addingTimeInterval(2))
        clock.pause(now: t0.addingTimeInterval(5))
        clock.resume(now: t0.addingTimeInterval(6))
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(8)), 4, accuracy: 0.001)
    }
}
