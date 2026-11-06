import XCTest
@testable import EngineKit

final class ClipPlacementTests: XCTestCase {
    private typealias Position = Project.MediaPosition

    func testAFullFrameClipCanSlideButStaysReachable() {
        let moved = Position(x: 0, y: 0, w: 1, h: 1).moved(dx: 0.3, dy: -5)
        XCTAssertEqual(moved.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.y, Position.minimumVisible - 1, accuracy: 0.0001)
        XCTAssertEqual(moved.w, 1)
    }

    func testResizeKeepsTheShapeWithinLimits() {
        let wide = Position(x: 0.1, y: 0.2, w: 0.4, h: 0.2)
        let bigger = wide.resized(toWidth: 0.6)
        XCTAssertEqual(bigger.h, 0.3, accuracy: 0.0001)
        XCTAssertEqual(bigger.x, 0.1)
        XCTAssertEqual(wide.resized(toWidth: 5).w, 1, accuracy: 0.0001)
        XCTAssertEqual(wide.resized(toWidth: 0).h, Position.minimumClipSize, accuracy: 0.0001)
    }

    func testTheVisiblePartStaysOnCanvasAndAnchored() {
        let card = CGRect(x: 0.5, y: 0.6, width: 0.4, height: 0.3)
        let frame = Position(x: 0, y: 0, w: 1, h: 1)
        XCTAssertEqual(frame.moved(dx: 5, dy: 0, keeping: card).x, 1 - Position.minimumVisible - 0.5, accuracy: 0.0001)
        XCTAssertEqual(frame.moved(dx: -5, dy: 0, keeping: card).x, Position.minimumVisible - 0.9, accuracy: 0.0001)

        let half = frame.resized(toWidth: 0.5, anchor: card.origin)
        XCTAssertEqual(half.x + card.minX * half.w, card.minX, accuracy: 0.0001)
        XCTAssertEqual(half.y + card.minY * half.h, card.minY, accuracy: 0.0001)
    }

    func testContentBoundsIgnoreTransparentPixels() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 60, y: 5, width: 30, height: 20)) // bottom-up: 25...45 from the top
        let bounds = try XCTUnwrap(VideoContentShape.opaqueBounds(of: try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(bounds.minX, 0.6, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 0.5, accuracy: 0.001)
        XCTAssertEqual(bounds.width, 0.3, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 0.4, accuracy: 0.001)

        let empty = try XCTUnwrap(CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        XCTAssertNil(VideoContentShape.opaqueBounds(of: empty))
    }

    func testValidationAllowsOffCanvasClipsOnly() {
        func error(_ position: Position) -> EditorError? {
            EditorValidation.validateClip(Project.TimelineClip(
                timelineIn: 0, content: .video(Project.VideoClipRef(path: "assets/a.mov", sourceOut: 4)), position: position))
        }
        XCTAssertNil(error(Position(x: -0.3, y: 0.4, w: 1, h: 1)))
        XCTAssertNotNil(error(Position(x: 0, y: 0, w: 1.2, h: 1)))
        XCTAssertNotNil(error(Position(x: -2, y: 0, w: 1, h: 1)))
    }
}
