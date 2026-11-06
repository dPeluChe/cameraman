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

    func testPerClipCameraPicksTheColumn() throws {
        let layout = CanvasLayout.defaultLayout(for: .sideBySide)
        let clipCamera = try XCTUnwrap(layout.placingCamera(onLeft: true).camera)
        let frame = try XCTUnwrap(layout.screenFrame(sourceSize: CGSize(width: 640, height: 360), canvas: canvas, camera: clipCamera))
        XCTAssertGreaterThan(frame.minX, canvas.width / 2)
    }

    func testOnlySideBySideHasAColumn() {
        XCTAssertNil(CanvasLayout.defaultLayout(for: .pip).screenColumn(in: canvas))
        XCTAssertNil(Layout(type: "side-by-side", camera: nil).screenColumn(in: canvas))
    }

    func testDecodesTheSpellingOlderMCPBuildsStored() throws {
        let json = Data(#"{"type":"side_by_side"}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Layout.self, from: json).isSideBySide)
    }

    func testCompositorDrawsTwoColumnsOnEitherSide() throws {
        let screen = tempDirectory.appendingPathComponent("screen.mov")
        let camera = tempDirectory.appendingPathComponent("camera.mov")
        try writeSolidVideo(to: screen, color: CIColor(red: 1, green: 0, blue: 0))
        try writeSolidVideo(to: camera, color: CIColor(red: 0, green: 0, blue: 1))

        let right = CanvasLayout.defaultLayout(for: .sideBySide)
        for (layout, screenX, cameraX) in [(right, 0.25, 0.75), (right.placingCamera(onLeft: true), 0.75, 0.25)] {
            let frame = try render(screen: screen, camera: camera, layout: layout)
            let pixel = { (x: Double, y: Double) in
                MotionTestSupport.pixel(frame, x: Int(x * Double(frame.width)), y: Int(y * Double(frame.height)))
            }
            XCTAssertGreaterThan(pixel(screenX, 0.5).r, 200, "screen in its column")
            XCTAssertGreaterThan(pixel(cameraX, 0.5).b, 200, "camera in its column")
            XCTAssertLessThan(pixel(cameraX, 0.5).r, 60, "screen must not run under the camera")
            XCTAssertLessThan(pixel(screenX, 0.05).r, 60, "screen is fit, not stretched to the canvas")
        }
    }

    func testOverlayDrawsUnderOrOverTheCamera() throws {
        let screen = tempDirectory.appendingPathComponent("screen.mov")
        let camera = tempDirectory.appendingPathComponent("camera.mov")
        let overlay = tempDirectory.appendingPathComponent("overlay.mov")
        try writeSolidVideo(to: screen, color: CIColor(red: 1, green: 0, blue: 0))
        try writeSolidVideo(to: camera, color: CIColor(red: 0, green: 0, blue: 1))
        try writeSolidVideo(to: overlay, color: CIColor(red: 0, green: 1, blue: 0))
        let layout = CanvasLayout.defaultLayout(for: .sideBySide)
        let center = { (frame: CGImage) in
            MotionTestSupport.pixel(frame, x: frame.width * 3 / 4, y: frame.height / 2)
        }

        let under = try render(screen: screen, camera: camera, layout: layout, overlay: (overlay, true))
        XCTAssertGreaterThan(center(under).b, 200, "the camera stays on top")

        let over = try render(screen: screen, camera: camera, layout: layout, overlay: (overlay, false))
        XCTAssertGreaterThan(center(over).g, 200, "B-roll still covers it")
    }

    // MARK: - Helpers

    private func render(screen: URL, camera: URL, layout: Layout, overlay: (url: URL, belowCamera: Bool)? = nil) throws -> CGImage {
        let composition = AVMutableComposition()
        let screenID = try addTrack(from: screen, to: composition)
        let cameraID = try addTrack(from: camera, to: composition)
        let overlaySources = try overlay.map {
            [MaskedVideoCompositionInstruction.VideoOverlaySource(
                trackID: try addTrack(from: $0.url, to: composition), opacity: 1, belowCamera: $0.belowCamera
            )]
        } ?? []
        let position = try XCTUnwrap(layout.camera)
        let source = CGSize(width: 640, height: 360)
        let frame = try XCTUnwrap(layout.screenFrame(sourceSize: source, canvas: canvas))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MaskedVideoCompositor.self
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [MaskedVideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            screenTrackID: screenID,
            cameraTrackID: cameraID,
            renderSize: canvas,
            screenTransform: Layout.fit(CGRect(origin: .zero, size: source), into: frame),
            screenFrame: frame,
            cameraTransform: PreviewEngine.cameraTransform(position: position, camSourceSize: source, renderSize: canvas),
            cameraRect: CGRect(x: position.x, y: position.y, width: position.w, height: position.h),
            maskShape: .none,
            cornerRadius: 0,
            layoutType: layout.type,
            backgroundType: "solid",
            backgroundValue: "#000000",
            videoOverlays: overlaySources
        )]

        let generator = AVAssetImageGenerator(asset: composition)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: CMTime(value: 1, timescale: 10), actualTime: nil)
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
}
