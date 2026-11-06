//
//  SideBySideLayoutTests.swift
//  EngineKitTests
//

import XCTest
import AVFoundation
import CoreImage
@testable import EngineKit

final class SideBySideLayoutTests: XCTestCase {
    private typealias Layout = Project.Canvas.Layout
    private let canvas = CGSize(width: 1280, height: 720)

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SideBySide_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testScreenTakesTheColumnOppositeTheCamera() throws {
        let right = CanvasLayout.defaultLayout(for: .sideBySide)
        XCTAssertFalse(right.isCameraOnLeft)
        let rightColumn = try XCTUnwrap(right.screenColumn(in: canvas))
        XCTAssertLessThanOrEqual(rightColumn.maxX, CGFloat(right.camera!.x) * canvas.width)

        let left = right.placingCamera(onLeft: true)
        XCTAssertTrue(left.isCameraOnLeft)
        let leftColumn = try XCTUnwrap(left.screenColumn(in: canvas))
        XCTAssertGreaterThanOrEqual(leftColumn.minX, CGFloat(left.camera!.x + left.camera!.w) * canvas.width)
        XCTAssertEqual(leftColumn.width, rightColumn.width, accuracy: 0.5)
    }

    func testOnlySideBySideHasAColumn() {
        XCTAssertNil(CanvasLayout.defaultLayout(for: .pip).screenColumn(in: canvas))
        XCTAssertNil(Layout(type: "side-by-side", camera: nil).screenColumn(in: canvas))
    }

    func testDecodesTheSpellingOlderMCPBuildsStored() throws {
        let json = Data(#"{"type":"side_by_side"}"#.utf8)
        let layout = try JSONDecoder().decode(Layout.self, from: json)
        XCTAssertTrue(layout.isSideBySide)
        XCTAssertNoThrow(try CanvasLayout.validateLayout(CanvasLayout.defaultLayout(for: .sideBySide), hasCamera: true))
    }

    func testCompositorDrawsTwoColumnsOnEitherSide() throws {
        let screen = tempDirectory.appendingPathComponent("screen.mov")
        let camera = tempDirectory.appendingPathComponent("camera.mov")
        try writeSolidVideo(to: screen, color: CIColor(red: 1, green: 0, blue: 0))
        try writeSolidVideo(to: camera, color: CIColor(red: 0, green: 0, blue: 1))

        let right = CanvasLayout.defaultLayout(for: .sideBySide)
        for (layout, screenX, cameraX) in [(right, 0.25, 0.75), (right.placingCamera(onLeft: true), 0.75, 0.25)] {
            let frame = try render(screen: screen, camera: camera, layout: layout)
            XCTAssertGreaterThan(frame.red(x: screenX, y: 0.5), 200, "screen in its column")
            XCTAssertGreaterThan(frame.blue(x: cameraX, y: 0.5), 200, "camera in its column")
            XCTAssertLessThan(frame.red(x: cameraX, y: 0.5), 60, "screen must not run under the camera")
            XCTAssertLessThan(frame.red(x: screenX, y: 0.05), 60, "screen is fit, not stretched to the canvas")
        }
    }

    // MARK: - Helpers

    private func render(screen: URL, camera: URL, layout: Layout) throws -> Frame {
        let composition = AVMutableComposition()
        let screenID = try addTrack(from: screen, to: composition)
        let cameraID = try addTrack(from: camera, to: composition)
        let position = try XCTUnwrap(layout.camera)
        let source = CGSize(width: 640, height: 360)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [MaskedVideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            screenTrackID: screenID,
            cameraTrackID: cameraID,
            renderSize: canvas,
            screenTransform: try XCTUnwrap(layout.screenColumnTransform(sourceSize: source, canvas: canvas)),
            screenFrame: layout.screenColumn(in: canvas),
            cameraTransform: PreviewEngine.cameraTransform(position: position, camSourceSize: source, renderSize: canvas),
            cameraRect: CGRect(x: position.x, y: position.y, width: position.w, height: position.h),
            maskShape: .none,
            cornerRadius: 0,
            layoutType: layout.type,
            backgroundType: "solid",
            backgroundValue: "#000000"
        )]

        let generator = AVAssetImageGenerator(asset: composition)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: CMTime(value: 1, timescale: 10), actualTime: nil)
        return try Frame(image)
    }

    private func addTrack(from url: URL, to composition: AVMutableComposition) throws -> CMPersistentTrackID {
        let asset = AVURLAsset(url: url)
        let source = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let track = try XCTUnwrap(composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
        return track.trackID
    }

    private func writeSolidVideo(to url: URL, color: CIColor) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixels = try XCTUnwrap(buffer)
        CIContext().render(CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 360)), to: pixels)

        for index in 0..<15 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30))
        }
        input.markAsFinished()
        let done = expectation(description: "written")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
    }

    private struct Frame {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            rgba = bytes
        }

        private func channel(_ offset: Int, x: Double, y: Double) -> UInt8 {
            rgba[(Int(y * Double(height)) * width + Int(x * Double(width))) * 4 + offset]
        }
        func red(x: Double, y: Double) -> UInt8 { channel(0, x: x, y: y) }
        func blue(x: Double, y: Double) -> UInt8 { channel(2, x: x, y: y) }
    }
}
