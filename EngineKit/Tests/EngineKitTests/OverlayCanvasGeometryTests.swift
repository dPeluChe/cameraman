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

    func testSnapsCenterWithinPixelThreshold() {
        let result = OverlayCanvasGeometry.snappedCenter(
            proposed: CGPoint(x: 0.504, y: 0.497),
            relativeSize: CGSize(width: 0.2, height: 0.1),
            scale: 1,
            rotationDegrees: 0,
            in: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(result.center, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(result.verticalGuide, 0.5)
        XCTAssertEqual(result.horizontalGuide, 0.5)
    }

    func testSnapsOverlayEdgeToSafeArea() {
        let result = OverlayCanvasGeometry.snappedCenter(
            proposed: CGPoint(x: 0.151, y: 0.8),
            relativeSize: CGSize(width: 0.2, height: 0.1),
            scale: 1,
            rotationDegrees: 0,
            in: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(result.center.x, 0.15, accuracy: 0.0001)
        XCTAssertEqual(result.verticalGuide, 0.05)
        XCTAssertNil(result.horizontalGuide)
    }

    func testConstrainKeepsRotatedOverlayInsideCanvas() {
        let result = OverlayCanvasGeometry.snappedCenter(
            proposed: CGPoint(x: 0, y: 0),
            relativeSize: CGSize(width: 0.4, height: 0.2),
            scale: 1,
            rotationDegrees: 90,
            in: CGSize(width: 1000, height: 1000)
        )

        XCTAssertEqual(result.center.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.center.y, 0.2, accuracy: 0.0001)
    }

    func testSafeAreaRectUsesNormalizedInset() {
        XCTAssertEqual(
            OverlayCanvasGeometry.safeAreaRect(in: CGSize(width: 1000, height: 500)),
            CGRect(x: 50, y: 25, width: 900, height: 450)
        )
    }
}
