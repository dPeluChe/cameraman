import XCTest
@testable import EngineKit

final class LiveAnnotationTests: XCTestCase {
    private func shape(_ kind: LiveAnnotation.Kind = .rect, _ points: [CGPoint], start: TimeInterval = 0, text: String? = nil) -> LiveAnnotation {
        LiveAnnotation(kind: kind, points: points, colorHex: "#FF3B30", lineWidth: 4, text: text, start: start)
    }

    func testDegenerateShapesAreDropped() {
        var log = LiveAnnotationLog()
        XCTAssertFalse(log.add(shape(.rect, [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5)])))
        XCTAssertFalse(log.add(shape(.pen, [CGPoint(x: 0.1, y: 0.1)])))
        XCTAssertFalse(log.add(shape(.text, [CGPoint(x: 0.1, y: 0.1)], text: "  \n")))
        XCTAssertTrue(log.isEmpty)
        XCTAssertTrue(log.add(shape(.text, [CGPoint(x: 0.1, y: 0.1)], text: "hola")))
    }

    func testUndoEndsTheLastVisibleShapeInsteadOfDeletingIt() {
        var log = LiveAnnotationLog()
        log.add(shape(.rect, [.zero, CGPoint(x: 0.2, y: 0.2)], start: 1))
        log.add(shape(.arrow, [.zero, CGPoint(x: 0.3, y: 0.3)], start: 2))
        XCTAssertTrue(log.undo(at: 5))
        XCTAssertEqual(log.items.count, 2)
        XCTAssertEqual(log.visible.map(\.kind), [.rect])
        XCTAssertEqual(log.items[1].end, 5)
        XCTAssertTrue(log.undo(at: 6))
        XCTAssertFalse(log.undo(at: 7), "nothing left to undo")
    }

    func testClearEndsEverythingVisibleOnce() {
        var log = LiveAnnotationLog()
        log.add(shape(.rect, [.zero, CGPoint(x: 0.2, y: 0.2)], start: 1))
        log.undo(at: 2)
        log.add(shape(.ellipse, [.zero, CGPoint(x: 0.4, y: 0.4)], start: 3))
        log.clear(at: 9)
        XCTAssertTrue(log.visible.isEmpty)
        XCTAssertEqual(log.items.map(\.end), [2, 9], "an already ended shape keeps its own end")
    }

    func testEndNeverPrecedesStart() {
        var log = LiveAnnotationLog()
        log.add(shape(.rect, [.zero, CGPoint(x: 0.2, y: 0.2)], start: 4))
        log.clear(at: 1)
        XCTAssertEqual(log.items[0].end, 4)
    }

    func testBoundsCoverTheStroke() {
        let pen = shape(.pen, [CGPoint(x: 0.2, y: 0.6), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.3, y: 0.4)])
        XCTAssertEqual(pen.bounds, CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.5))
    }

    func testRoundTripsThroughJSON() throws {
        var log = LiveAnnotationLog()
        log.add(shape(.text, [CGPoint(x: 0.25, y: 0.5)], start: 1.5, text: "aquí"))
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(LiveAnnotationLog.self, from: data), log)
    }
}
