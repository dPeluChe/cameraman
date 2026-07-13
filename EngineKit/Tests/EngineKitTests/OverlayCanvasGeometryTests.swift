import CoreGraphics
import XCTest
@testable import EngineKit

final class OverlayCanvasGeometryTests: XCTestCase {
    func testViewPointRoundTripsAcrossCanvasFormats() throws {
        for size in [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 1080, height: 1080)
        ] {
            let viewPoint = OverlayCanvasGeometry.viewPoint(x: 0.2, y: 0.75, in: size)
            let normalized = try XCTUnwrap(
                OverlayCanvasGeometry.normalizedPoint(fromViewPoint: viewPoint, in: size)
            )
            XCTAssertEqual(normalized.x, 0.2, accuracy: 0.0001)
            XCTAssertEqual(normalized.y, 0.75, accuracy: 0.0001)
        }
    }

    func testRenderPointFlipsTopLeftModelYForCoreGraphics() {
        let size = CGSize(width: 1000, height: 500)
        let point = OverlayCanvasGeometry.renderPoint(x: 0.2, y: 0.1, in: size)

        XCTAssertEqual(point.x, 200)
        XCTAssertEqual(point.y, 450)
    }

    func testNormalizedPointClampsDropsToCanvas() throws {
        let point = try XCTUnwrap(OverlayCanvasGeometry.normalizedPoint(
            fromViewPoint: CGPoint(x: -40, y: 700),
            in: CGSize(width: 1000, height: 500)
        ))

        XCTAssertEqual(point, CGPoint(x: 0, y: 1))
    }

    func testViewRectUsesRelativeSizeAndScale() {
        let rect = OverlayCanvasGeometry.viewRect(
            x: 0.5,
            y: 0.5,
            relativeSize: CGSize(width: 0.2, height: 0.1),
            scale: 1.5,
            in: CGSize(width: 1000, height: 500)
        )

        XCTAssertEqual(rect, CGRect(x: 350, y: 212.5, width: 300, height: 75))
    }
}
