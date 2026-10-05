import XCTest
import CoreImage
import CoreGraphics
@testable import EngineKit

/// Renders real pixels: the point of region blur is that the rest of the frame stays untouched, and
/// the vertical axis is easy to flip (project coordinates are top-left, CoreImage's are bottom-left).
final class RegionBlurTests: XCTestCase {
    private let side = 100
    private let context = CIContext(options: [.useSoftwareRenderer: true])

    /// White in the top quarter (rows 0..<25 from the top), black below: one hard horizontal edge at y = 25.
    private func frame() -> CIImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: side - 25, width: side, height: 25))   // CG origin is bottom-left
        return CIImage(cgImage: ctx.makeImage()!)
    }

    private func luminance(_ image: CIImage, x: Int, yFromTop: Int) -> Double {
        var px = [UInt8](repeating: 0, count: 4)
        let rect = CGRect(x: x, y: side - 1 - yFromTop, width: 1, height: 1)
        context.render(image, toBitmap: &px, rowBytes: 4, bounds: rect, format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return Double(px[0]) / 255
    }

    private func blur(_ parameters: [String: Double]) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        let config = AdjustmentConfig(kind: "gaussianBlur", target: .frame, parameters: parameters, start: 0, end: 10)
        return AdjustmentRenderer.apply([config], target: .frame, to: frame(), at: 1, extent: extent)
    }

    func testWholeLayerBlurSoftensTheEdge() {
        let out = blur(["radius": 8])
        let atEdge = luminance(out, x: 50, yFromTop: 25)
        XCTAssertGreaterThan(atEdge, 0.05)
        XCTAssertLessThan(atEdge, 0.95)
    }

    /// Region = top half in top-left coordinates. The edge (y = 25) is inside it, so it softens; the
    /// bottom is outside and stays black. If y were not flipped, the region would be the bottom half
    /// and the edge would stay hard.
    func testBlurIsConfinedToTheRegionWithATopLeftOrigin() {
        let out = blur(["radius": 8, "x": 0, "y": 0, "w": 1, "h": 0.5])
        let atEdge = luminance(out, x: 50, yFromTop: 25)
        XCTAssertGreaterThan(atEdge, 0.05, "the edge is inside the region and must soften")
        XCTAssertLessThan(atEdge, 0.95)
        XCTAssertEqual(luminance(out, x: 50, yFromTop: 90), 0, accuracy: 0.001, "below the region stays untouched")
    }

    func testPixelsOutsideTheRegionAreIdenticalToTheSource() {
        // Region covers only the right half; a whole-layer blur would soften the edge at x = 20 too.
        let out = blur(["radius": 30, "x": 0.5, "y": 0, "w": 0.5, "h": 1])
        XCTAssertEqual(luminance(out, x: 20, yFromTop: 25), luminance(frame(), x: 20, yFromTop: 25), accuracy: 0.001)
        XCTAssertNotEqual(luminance(out, x: 70, yFromTop: 25), luminance(frame(), x: 70, yFromTop: 25), accuracy: 0.02)
    }

    func testIncompleteRegionFallsBackToWholeLayer() {
        XCTAssertNil(AdjustmentRenderer.blurRegion(from: ["x": 0.1, "y": 0.1], in: .init(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertNil(AdjustmentRenderer.blurRegion(from: ["x": 0, "y": 0, "w": 0, "h": 1], in: .init(x: 0, y: 0, width: 10, height: 10)))
    }

    func testValidationRequiresAllFourRegionParametersInsideTheFrame() {
        func problem(_ p: [String: Double]) -> EditorError? {
            EditorValidation.validateAdjustment(
                Project.Adjustment(kind: .gaussianBlur, target: .frame, parameters: p), clipDuration: 10)
        }
        XCTAssertNil(problem(["radius": 8]))
        XCTAssertNil(problem(["radius": 8, "x": 0.1, "y": 0.1, "w": 0.5, "h": 0.5]))
        XCTAssertNotNil(problem(["radius": 8, "x": 0.1, "y": 0.1]), "a half-specified region would blur everything")
        XCTAssertNotNil(problem(["x": 0.6, "y": 0, "w": 0.6, "h": 1]), "extends past the right edge")
        XCTAssertNotNil(problem(["x": 0, "y": 0, "w": 0, "h": 1]))
    }
}
