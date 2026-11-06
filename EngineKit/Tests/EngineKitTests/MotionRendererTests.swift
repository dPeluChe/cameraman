import XCTest
import AVFoundation
@testable import EngineKit

@MainActor
final class MotionRendererTests: XCTestCase {
    private let squareHTML = """
    <html><head><style>
    html, body { margin: 0; background: transparent; }
    #box { position: absolute; top: 40px; left: 0; width: 40px; height: 40px; background: rgb(255,0,0);
           animation: slide 1s linear forwards; }
    @keyframes slide { from { transform: translateX(0); } to { transform: translateX(160px); } }
    </style></head><body><div id="box"></div></body></html>
    """

    private func tempURL(_ name: String = "motion.mov") -> URL { MotionTestSupport.tempURL(name) }
    private func frame(of url: URL, at seconds: Double) throws -> CGImage { try MotionTestSupport.frame(of: url, at: seconds) }
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) { MotionTestSupport.pixel(image, x: x, y: y) }

    func testContentShapeFollowsTheOpaqueAreaOverTime() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await MotionRenderer.render(html: squareHTML, to: url, options: MotionRenderOptions(width: 200, height: 100, fps: 10))

        let shape = try await XCTUnwrap(VideoContentShape.measure(url: url))
        XCTAssertEqual(shape.naturalSize, CGSize(width: 200, height: 100))
        XCTAssertEqual(shape.bounds.minY, 0.4, accuracy: 0.03)
        XCTAssertEqual(shape.bounds.maxY, 0.8, accuracy: 0.03)
        XCTAssertGreaterThan(shape.bounds.width, 0.6, "the box slides across most of the frame")
    }

    func testRendersTransparentVideoThatMoves() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let options = MotionRenderOptions(width: 200, height: 100, fps: 10)
        let result = try await MotionRenderer.render(html: squareHTML, to: url, options: options)

        XCTAssertEqual(result.frameCount, 10)
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await XCTUnwrap(track).load(.naturalSize)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 100)
        let length = try await asset.load(.duration).seconds
        XCTAssertEqual(length, 1.0, accuracy: 0.11)

        let first = try frame(of: url, at: 0)
        let last = try frame(of: url, at: 0.9)
        XCTAssertEqual(first.width, 200, "frames are rendered at the asked pixel size, not at the screen's scale")
        // The empty corner stays transparent; the square is opaque red where it is.
        XCTAssertEqual(pixel(first, x: 190, y: 5).a, 0, "background must keep its alpha")
        let atStart = pixel(first, x: 20, y: 60)
        XCTAssertGreaterThan(atStart.a, 200)
        XCTAssertGreaterThan(atStart.r, 200)
        XCTAssertEqual(pixel(first, x: 170, y: 60).a, 0)
        // 0.9s of a 160px slide: the square now covers x≈144-184.
        XCTAssertGreaterThan(pixel(last, x: 170, y: 60).a, 200)
        XCTAssertEqual(pixel(last, x: 20, y: 60).a, 0)
    }

    /// The whole path an agent uses: render a motion, import it as a clip over footage, export.
    func testMotionIsBlendedOverFootageOnExport() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("motion-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ProjectStore(baseDirectory: base)
        let projectId = try await store.createEmptyProject(name: "motion e2e")
        let directory = store.baseDirectory.appendingPathComponent(projectId.uuidString)
        let assets = directory.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        // Opaque blue footage, 16:9 like the canvas, and a red square sliding over it.
        let options = MotionRenderOptions(width: 640, height: 360, fps: 10)
        let footage = "<html><body style=\"margin:0;background:rgb(0,0,255)\"></body></html>"
        _ = try await MotionRenderer.render(html: footage, to: assets.appendingPathComponent("footage.mov"),
                                            options: MotionRenderOptions(width: 640, height: 360, fps: 10, duration: 1))
        let slide = squareHTML.replacingOccurrences(of: "top: 40px", with: "top: 160px")
            .replacingOccurrences(of: "translateX(160px)", with: "translateX(500px)")
        _ = try await MotionRenderer.render(html: slide, to: assets.appendingPathComponent("motion.mov"), options: options)

        var project = try await store.loadProject(projectId: projectId)
        var editor = EditorModel(project: project)
        var result = await editor.importVideoClip(path: "assets/footage.mov", duration: 1, at: 0)
        project = try XCTUnwrap(result.getProject())
        editor = EditorModel(project: project)
        result = await editor.importVideoClip(path: "assets/motion.mov", duration: 1, at: 0)
        try await store.saveProject(try XCTUnwrap(result.getProject()))

        let queue = JobQueue()
        let engine = ExportEngine(jobQueue: queue, projectStore: store)
        let jobId = try await engine.export(projectId: projectId, preset: .web1080h264,
                                            options: ExportOptions(outputFilename: "out.mp4"))
        var status = await queue.getJobStatus(jobId: jobId)
        for _ in 0..<240 where status != .success && status != .failed {
            try await Task.sleep(nanoseconds: 250_000_000)
            status = await queue.getJobStatus(jobId: jobId)
        }
        XCTAssertEqual(status, .success)

        let out = directory.appendingPathComponent("renders/out.mp4")
        let frameAt = try frame(of: out, at: 0.6)
        // 1920x1080 canvas, square top at 160/360 of the height and x≈300/640 of the width at 0.6s.
        let onSquare = pixel(frameAt, x: Int(1920.0 * 320 / 640), y: Int(1080.0 * 180 / 360))
        let onFootage = pixel(frameAt, x: 100, y: 100)
        XCTAssertGreaterThan(onSquare.r, 180, "motion pixel must show over the footage")
        XCTAssertLessThan(onSquare.b, 80)
        XCTAssertGreaterThan(onFootage.b, 180, "transparent motion pixels must leave the footage visible")
        XCTAssertLessThan(onFootage.r, 60)
    }

    func testSameInputGivesSameFrames() async throws {
        let a = tempURL("a.mov"), b = tempURL("b.mov")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let options = MotionRenderOptions(width: 200, height: 100, fps: 10)
        _ = try await MotionRenderer.render(html: squareHTML, to: a, options: options)
        _ = try await MotionRenderer.render(html: squareHTML, to: b, options: options)
        let fa = try frame(of: a, at: 0.5), fb = try frame(of: b, at: 0.5)
        for x in stride(from: 0, to: 200, by: 7) {
            let pa = pixel(fa, x: x, y: 60), pb = pixel(fb, x: x, y: 60)
            XCTAssertEqual(pa.a, pb.a, "x=\(x)")
            XCTAssertEqual(pa.r, pb.r, "x=\(x)")
        }
    }

    func testExplicitHfContractWins() async throws {
        let html = """
        <html><body style="margin:0;background:transparent"><div id="b" style="width:100px;height:100px;background:#0f0"></div>
        <script>window.__hf = { duration: 0.5, seek(t) { document.getElementById('b').style.opacity = String(1 - t * 2); } };</script>
        </body></html>
        """
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await MotionRenderer.render(html: html, to: url, options: MotionRenderOptions(width: 100, height: 100, fps: 10))
        XCTAssertEqual(result.frameCount, 5)
        XCTAssertGreaterThan(pixel(try frame(of: url, at: 0), x: 50, y: 50).a, 200)
        XCTAssertLessThan(pixel(try frame(of: url, at: 0.4), x: 50, y: 50).a, 120)
    }

    func testPageWithoutDurationIsRejected() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await MotionRenderer.render(html: "<html><body>static</body></html>", to: url,
                                                options: MotionRenderOptions(width: 100, height: 100, fps: 10))
            XCTFail("a page with nothing to animate has no duration")
        } catch let error as MotionError {
            guard case .invalidOptions = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testColorsSurviveTheVideo() async throws {
        let html = """
        <html><body style="margin:0;background:rgb(51,102,153)">
        <script>window.__hf = { duration: 0.3, seek() {} };</script></body></html>
        """
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await MotionRenderer.render(html: html, to: url, options: MotionRenderOptions(width: 100, height: 100, fps: 10))
        let color = pixel(try frame(of: url, at: 0.1), x: 50, y: 50)
        XCTAssertEqual(Int(color.r), 51, accuracy: 3)
        XCTAssertEqual(Int(color.g), 102, accuracy: 3)
        XCTAssertEqual(Int(color.b), 153, accuracy: 3)
    }

    func testNonFiniteDurationIsRejected() async throws {
        let url = tempURL()
        for value in ["Infinity", "NaN", "1e300"] {
            let html = "<html><body><script>window.__hf = { duration: \(value), seek() {} };</script></body></html>"
            do {
                _ = try await MotionRenderer.render(html: html, to: url, options: MotionRenderOptions(width: 100, height: 100, fps: 10))
                XCTFail("\(value) must not render")
            } catch let error as MotionError {
                guard case .invalidOptions = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testStuckPageTimesOut() async throws {
        for seek in ["return new Promise(() => {});", "while (true) {}"] {
            let html = "<html><body><script>window.__hf = { duration: 1, seek() { \(seek) } };</script></body></html>"
            let url = tempURL()
            let options = MotionRenderOptions(width: 100, height: 100, fps: 10, stepTimeout: 0.5)
            do {
                _ = try await MotionRenderer.render(html: html, to: url, options: options)
                XCTFail("a page that never answers must fail")
            } catch let error as MotionError {
                guard case .pageFailed(let reason) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(reason.contains("timed out"), reason)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no partial file")
        }
    }

    func testCancelStopsAtAStuckPage() async throws {
        let html = "<html><body><script>window.__hf = { duration: 1, seek() { return new Promise(() => {}); } };</script></body></html>"
        let url = tempURL()
        let options = MotionRenderOptions(width: 100, height: 100, fps: 10, stepTimeout: 60)
        let render = Task { try await MotionRenderer.render(html: html, to: url, options: options) }
        try await Task.sleep(nanoseconds: 500_000_000)
        render.cancel()
        let started = Date()
        let result = await render.result
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "cancel must not wait for the step timeout")
        guard case .failure(let error) = result, error is CancellationError else { return XCTFail("\(result)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOddSizeIsRejected() async throws {
        do {
            _ = try await MotionRenderer.render(html: squareHTML, to: tempURL(), options: MotionRenderOptions(width: 101, height: 100))
            XCTFail("expected invalid options")
        } catch is MotionError {}
    }
}
