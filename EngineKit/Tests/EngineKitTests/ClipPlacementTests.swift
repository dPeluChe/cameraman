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
