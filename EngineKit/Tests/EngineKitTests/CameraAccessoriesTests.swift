import XCTest
import CoreImage
import AppKit
@testable import EngineKit

final class CameraAccessoriesTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    private func anchors(roll: CGFloat = 0) -> FaceAnchors {
        let mid = CGPoint(x: 400, y: 260)
        let half: CGFloat = 80
        let left = CGPoint(x: mid.x - half * cos(roll), y: mid.y - half * sin(roll))
        let right = CGPoint(x: mid.x + half * cos(roll), y: mid.y + half * sin(roll))
        return FaceAnchors(leftEye: left, rightEye: right, faceBox: CGRect(x: 300, y: 110, width: 200, height: 260))
    }

    /// Bounding box of the non-transparent pixels after drawing `kinds` on a transparent frame.
    private func inkBounds(_ kinds: [Project.CameraAccessories.Kind], anchors: FaceAnchors, scale: Double = 1) -> CGRect? {
        let blank = CIImage(color: .clear).cropped(to: frame)
        let result = AccessoryRenderer.apply(.init(kinds: kinds, scale: scale), anchors: anchors, to: blank)
        let width = Int(frame.width), height = Int(frame.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(result, toBitmap: &rgba, rowBytes: width * 4, bounds: frame, format: .RGBA8, colorSpace: nil)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        // Bitmap rows run top-down; report bottom-left coordinates like the anchors.
        return maxX < 0 ? nil : CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX, height: maxY - minY)
    }

    func testGlassesSitOnTheEyes() throws {
        let bounds = try XCTUnwrap(inkBounds([.glasses], anchors: anchors()))
        XCTAssertEqual(bounds.midX, 400, accuracy: 12)
        XCTAssertEqual(bounds.midY, 260, accuracy: 25)
        XCTAssertGreaterThan(bounds.width, 160)      // wider than the eye distance
    }

    func testHatSitsAboveTheFaceAndCrownToo() throws {
        for kind in [Project.CameraAccessories.Kind.partyHat, .crown] {
            let bounds = try XCTUnwrap(inkBounds([kind], anchors: anchors()), "\(kind)")
            XCTAssertGreaterThan(bounds.minY, 260, "\(kind) must start above the eyes")
            XCTAssertEqual(bounds.midX, 400, accuracy: 20, "\(kind)")
        }
    }

    func testScaleGrowsTheDrawing() throws {
        let small = try XCTUnwrap(inkBounds([.sunglasses], anchors: anchors(), scale: 0.7))
        let large = try XCTUnwrap(inkBounds([.sunglasses], anchors: anchors(), scale: 1.4))
        XCTAssertGreaterThan(large.width, small.width * 1.8)
    }

    func testTiltFollowsTheEyeLine() throws {
        let level = try XCTUnwrap(inkBounds([.glasses], anchors: anchors(roll: 0)))
        let tilted = try XCTUnwrap(inkBounds([.glasses], anchors: anchors(roll: 0.5)))
        XCTAssertGreaterThan(tilted.height, level.height + 40)   // a tilted pair covers more rows
    }

    func testNoAccessoriesLeavesTheFrameAlone() {
        XCTAssertNil(inkBounds([], anchors: anchors()))
    }

    func testToggleAndRoundTrip() throws {
        var accessories = Project.CameraAccessories()
        accessories.toggle(.crown)
        accessories.toggle(.glasses)
        accessories.toggle(.crown)
        XCTAssertEqual(accessories.kinds, [.glasses])
        let data = try JSONEncoder().encode(accessories)
        XCTAssertEqual(try JSONDecoder().decode(Project.CameraAccessories.self, from: data), accessories)
    }

    /// Real frame: set CAMERA_BG_SAMPLE to a photo of a face; CAMERA_ACC_OUT (optional) saves the result.
    func testFaceTrackerAndRenderOnARealFrame() throws {
        let sample = ProcessInfo.processInfo.environment["CAMERA_BG_SAMPLE"]
        try XCTSkipUnless(sample?.isEmpty == false, "set CAMERA_BG_SAMPLE to run this check")
        let image = try XCTUnwrap(CIImage(contentsOf: URL(fileURLWithPath: try XCTUnwrap(sample))))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CIContext().render(image, to: pixelBuffer)

        let found = try XCTUnwrap(FaceTracker().anchors(for: pixelBuffer, frameKey: 1))
        XCTAssertLessThan(found.leftEye.x, found.rightEye.x)
        XCTAssertTrue(found.faceBox.contains(found.leftEye) && found.faceBox.contains(found.rightEye))

        if let out = ProcessInfo.processInfo.environment["CAMERA_ACC_OUT"], !out.isEmpty {
            let drawn = AccessoryRenderer.apply(.init(kinds: [.sunglasses, .partyHat]), anchors: found, to: image)
            let rep = NSBitmapImageRep(ciImage: drawn)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
    }
}
