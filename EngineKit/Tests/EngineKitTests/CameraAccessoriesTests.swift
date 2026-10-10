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
            let svg = try writeSVG(in: makeDirectory())
            let logo = Project.CustomAccessory(name: "logo", assetPath: "x", anchor: .bottomCenter, size: 0.3)
            let drawn = AccessoryRenderer.apply(.init(kinds: [.sunglasses, .partyHat], custom: [logo]), anchors: found, images: [logo.id: svg], to: image)
            let rep = NSBitmapImageRep(ciImage: drawn)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
    }

    // MARK: - Custom images (logo, stickers)

    private func makeDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("accessory-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A red 2:1 SVG.
    private func writeSVG(in dir: URL, name: String = "logo.svg", color: String = "#FF0000") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
          <rect width="200" height="100" fill="\(color)"/>
        </svg>
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Bounds of what a custom accessory draws on a transparent frame.
    private func customBounds(_ item: Project.CustomAccessory, url: URL, anchors: FaceAnchors?) -> CGRect? {
        let blank = CIImage(color: .clear).cropped(to: frame)
        let accessories = Project.CameraAccessories(custom: [item])
        let result = AccessoryRenderer.apply(accessories, anchors: anchors, images: [item.id: url], to: blank)
        let width = Int(frame.width), height = Int(frame.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(result, toBitmap: &rgba, rowBytes: width * 4, bounds: frame, format: .RGBA8, colorSpace: nil)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX, height: maxY - minY)
    }

    func testSVGLogoPinnedToTheBottomCenterWithoutAFace() throws {
        let url = try writeSVG(in: makeDirectory())
        let item = Project.CustomAccessory(name: "logo", assetPath: "assets/logo.svg", anchor: .bottomCenter, size: 0.25)
        let bounds = try XCTUnwrap(customBounds(item, url: url, anchors: nil))
        XCTAssertEqual(bounds.width, 200, accuracy: 6)          // 25% of the 800 px frame
        XCTAssertEqual(bounds.height, 100, accuracy: 6)         // keeps the 2:1 aspect
        XCTAssertEqual(bounds.midX, 400, accuracy: 4)
        XCTAssertLessThan(bounds.minY, 40)                      // sits at the bottom with a small margin
        XCTAssertGreaterThan(bounds.minY, 5)
    }

    func testFrameCornersAndOffset() throws {
        let url = try writeSVG(in: makeDirectory())
        let topLeft = try XCTUnwrap(customBounds(.init(name: "a", assetPath: "x", anchor: .topLeft, size: 0.2), url: url, anchors: nil))
        XCTAssertLessThan(topLeft.minX, 40)
        XCTAssertGreaterThan(topLeft.maxY, frame.height - 40)
        let moved = try XCTUnwrap(customBounds(.init(name: "a", assetPath: "x", anchor: .center, size: 0.2, offsetX: 0.1), url: url, anchors: nil))
        XCTAssertEqual(moved.midX, 400 + 80, accuracy: 6)       // 10% of the frame width to the right
    }

    func testFaceAnchoredPiecesNeedAFace() throws {
        let url = try writeSVG(in: makeDirectory())
        let hat = Project.CustomAccessory(name: "hat", assetPath: "x", anchor: .headTop, size: 0.9)
        XCTAssertNil(customBounds(hat, url: url, anchors: nil))
        let bounds = try XCTUnwrap(customBounds(hat, url: url, anchors: anchors()))
        XCTAssertGreaterThan(bounds.minY, 260)                  // above the eyes
        XCTAssertEqual(bounds.midX, 400, accuracy: 6)
    }

    func testOpacityFadesTheImage() throws {
        let url = try writeSVG(in: makeDirectory())
        let item = Project.CustomAccessory(name: "logo", assetPath: "x", anchor: .center, size: 0.2, opacity: 0.4)
        let blank = CIImage(color: .clear).cropped(to: frame)
        let result = AccessoryRenderer.apply(.init(custom: [item]), anchors: nil, images: [item.id: url], to: blank)
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(result, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 400, y: 300, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        XCTAssertEqual(Double(rgba[3]), 0.4 * 255, accuracy: 12)
    }

    func testNeedsFaceOnlyForFacePieces() {
        var accessories = Project.CameraAccessories(custom: [.init(name: "logo", assetPath: "x", anchor: .bottomRight)])
        XCTAssertTrue(accessories.isActive)
        XCTAssertFalse(accessories.needsFace)
        accessories.toggle(.crown)
        XCTAssertTrue(accessories.needsFace)
        XCTAssertTrue(Project.CustomAccessory.Anchor.eyes.followsFace)
        XCTAssertFalse(Project.CustomAccessory.Anchor.center.followsFace)
    }

    func testOldProjectsWithoutCustomDecodeAndPathsResolve() throws {
        let legacy = try JSONDecoder().decode(Project.CameraAccessories.self, from: Data(#"{"kinds":["glasses"],"scale":1.2}"#.utf8))
        XCTAssertEqual(legacy.kinds, [.glasses])
        XCTAssertTrue(legacy.custom.isEmpty)

        var project = Project(
            projectId: ProjectId(), name: "p",
            timeline: Project.Timeline(duration: 1, segments: []),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                layout: Project.Canvas.Layout(type: "pip", camera: nil)
            )
        )
        XCTAssertFalse(project.hasCameraEffects)
        project.cameraAccessories.custom = [.init(name: "logo", assetPath: "assets/logo.svg")]
        XCTAssertTrue(project.hasCameraEffects)
        let resolved = project.resolvingAccessoryPaths(in: URL(fileURLWithPath: "/tmp/proj"))
        XCTAssertEqual(resolved.cameraAccessories.custom[0].assetPath, "/tmp/proj/assets/logo.svg")
    }

    func testAnchorChangeResetsSizeAndFramePivots() {
        var item = Project.CustomAccessory(name: "logo", assetPath: "x", anchor: .bottomCenter, size: 0.3)
        item.setAnchor(.headTop)
        XCTAssertEqual(item.size, 0.9)
        item.setAnchor(.topRight)
        XCTAssertEqual(item.size, 0.3)
        XCTAssertEqual(Project.CustomAccessory.Anchor.topRight.framePivot, CGPoint(x: 1, y: 1))
        XCTAssertNil(Project.CustomAccessory.Anchor.eyes.framePivot)
    }

    func testStagingKeepsADifferentFileWithTheSameName() throws {
        let project = makeDirectory()
        let first = try writeSVG(in: makeDirectory(), color: "#FF0000")
        let second = try writeSVG(in: makeDirectory(), color: "#0000FF")

        let a = try ProjectLibrary.stageAsset(from: first, intoProjectDirectory: project, keepExisting: true)
        let b = try ProjectLibrary.stageAsset(from: second, intoProjectDirectory: project, keepExisting: true)
        let again = try ProjectLibrary.stageAsset(from: first, intoProjectDirectory: project, keepExisting: true)

        XCTAssertEqual(a, "assets/logo.svg")
        XCTAssertNotEqual(a, b)                  // a different logo with the same name gets its own file
        XCTAssertEqual(a, again)                 // the same file again reuses the existing copy
        XCTAssertTrue(try String(contentsOf: project.appendingPathComponent(a)).contains("#FF0000"))
    }
}
