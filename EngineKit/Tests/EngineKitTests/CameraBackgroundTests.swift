import XCTest
import CoreImage
@testable import EngineKit

final class CameraBackgroundTests: XCTestCase {
    private let size = CGRect(x: 0, y: 0, width: 8, height: 8)
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Red frame; matte is white on the left half (the "person"), black on the right.
    private func render(_ background: Project.CameraBackground) -> (left: [UInt8], right: [UInt8]) {
        let frame = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: size)
        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 8))
        let black = CIImage(color: .black).cropped(to: CGRect(x: 4, y: 0, width: 4, height: 8))
        let matte = white.composited(over: black)

        let out = MaskedVideoCompositor().applyBackground(background, to: frame, matte: matte)
        func pixel(_ x: Int) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            context.render(out, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: x, y: 4, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
            return rgba
        }
        return (pixel(1), pixel(6))
    }

    func testRemoveMakesBackgroundTransparentAndKeepsPerson() {
        let result = render(.init(mode: .remove))
        XCTAssertEqual(result.left[3], 255)
        XCTAssertEqual(result.left[0], 255)
        XCTAssertEqual(result.right[3], 0)
    }

    func testColorReplacesBackgroundOnly() {
        let result = render(.init(mode: .color, colorHex: "#0000FF"))
        XCTAssertEqual(result.left[0], 255)            // person still red
        XCTAssertEqual(result.right[2], 255)           // background now blue
        XCTAssertEqual(result.right[0], 0)
    }

    func testBlurKeepsPersonSharp() {
        let result = render(.init(mode: .blur, blurRadius: 10))
        XCTAssertEqual(result.left[0], 255)
        XCTAssertEqual(result.left[3], 255)
    }

    func testOffLeavesImageAlone() {
        let result = render(.init(mode: .off))
        XCTAssertEqual(result.right[0], 255)
    }

    func testProjectRoundTripAndOldProjectsDecodeWithoutTheField() throws {
        var project = Project(
            projectId: ProjectId(), name: "p",
            timeline: Project.Timeline(duration: 1, segments: []),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                layout: Project.Canvas.Layout(type: "pip", camera: nil)
            )
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        legacy.removeValue(forKey: "cameraBackground")
        let plain = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: plain).cameraBackground, Project.CameraBackground())

        project.cameraBackground = .init(mode: .blur, blurRadius: 30, colorHex: "#112233")
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data).cameraBackground, project.cameraBackground)
    }

    /// Real frame check: point CAMERA_BG_SAMPLE at a PNG/JPEG of a person in front of a background.
    func testSegmenterFindsAPersonInARealFrame() throws {
        let sample = ProcessInfo.processInfo.environment["CAMERA_BG_SAMPLE"]
        try XCTSkipUnless(sample?.isEmpty == false, "set CAMERA_BG_SAMPLE to run this check")
        let path = try XCTUnwrap(sample)
        let image = try XCTUnwrap(CIImage(contentsOf: URL(fileURLWithPath: path)))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CIContext().render(image, to: pixelBuffer)

        let segmenter = PersonSegmenter()
        let first = try XCTUnwrap(segmenter.mask(for: pixelBuffer, frameKey: 1, quality: .balanced))
        XCTAssertEqual(first.extent.size, image.extent.size)

        // Mean matte value = fraction of the frame that is person.
        let average = first.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: first.extent)])
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext().render(average, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
        let coverage = Double(rgba[0]) / 255
        XCTAssertGreaterThan(coverage, 0.10, "a person should cover a visible part of the frame")
        XCTAssertLessThan(coverage, 0.80)

        let start = CFAbsoluteTimeGetCurrent()
        let again = segmenter.mask(for: pixelBuffer, frameKey: 1, quality: .balanced)
        XCTAssertNotNil(again)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.05, "same frame key must hit the cache")
    }
}
