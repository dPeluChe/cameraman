//
//  MotionRenderer.swift
//  EngineKit
//
//  Renders a code-built animation (HTML/CSS/JS) to a transparent video. Time is driven from
//  outside: the page exposes `window.__hf = { duration, seek(t) }`, the renderer seeks, snaps the
//  frame and encodes it, so the same page gives the same frames. See docs/FEATURES/MOTION.md.
//

import AppKit
import AVFoundation
import WebKit

public struct MotionRenderOptions: Sendable {
    public var width: Int
    public var height: Int
    public var fps: Int
    /// Overrides the duration the page reports. Seconds.
    public var duration: TimeInterval?
    /// Longest wait for the page to load, seek or paint one frame. Seconds.
    public var stepTimeout: TimeInterval

    public init(width: Int = 1920, height: Int = 1080, fps: Int = 30, duration: TimeInterval? = nil,
                stepTimeout: TimeInterval = 15) {
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration
        self.stepTimeout = stepTimeout
    }
}

public struct MotionRenderResult: Sendable {
    public let frameCount: Int
    public let duration: TimeInterval
}

public enum MotionError: LocalizedError {
    case invalidOptions(String)
    case pageFailed(String)
    case frameFailed(Int)
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOptions(let reason): return "Invalid motion options: \(reason)"
        case .pageFailed(let reason): return "The motion page failed to load: \(reason)"
        case .frameFailed(let index): return "Could not capture frame \(index)."
        case .writerFailed(let reason): return "Could not write the video: \(reason)"
        }
    }
}

@MainActor
public final class MotionRenderer {
    private static let maxFrames = 60 * 60

    private let webView: WKWebView
    private let window: NSWindow
    private let loader = PageLoader()
    private let stepTimeout: TimeInterval

    private init(width: Int, height: Int, stepTimeout: TimeInterval) {
        self.stepTimeout = stepTimeout
        let configuration = WKWebViewConfiguration()
        // Pages must not see what an earlier render left in cookies or storage.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        // Transparent page: the video keeps the alpha the page leaves.
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = loader
        // A view outside any window may skip painting; park it far off screen.
        window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFrontRegardless()
    }

    /// Renders `html` to a HEVC-with-alpha .mov at `url`.
    public static func render(
        html: String, to url: URL, options: MotionRenderOptions = MotionRenderOptions()
    ) async throws -> MotionRenderResult {
        guard options.width > 0, options.height > 0, options.width % 2 == 0, options.height % 2 == 0 else {
            throw MotionError.invalidOptions("width and height must be positive and even")
        }
        guard (1...120).contains(options.fps) else { throw MotionError.invalidOptions("fps must be 1-120") }
        // MCP renders run while the agent's app is in front; App Nap would throttle the page.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Rendering a motion graphic")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let renderer = MotionRenderer(width: options.width, height: options.height, stepTimeout: options.stepTimeout)
        defer { renderer.close() }
        return try await renderer.render(html: html, to: url, options: options)
    }

    private func close() {
        webView.stopLoading()
        window.contentView = nil
        window.orderOut(nil)
    }

    private func render(html: String, to url: URL, options: MotionRenderOptions) async throws -> MotionRenderResult {
        try await load(html)
        let reported = try await prepareSeekContract()
        let duration = options.duration ?? reported
        let exactFrames = duration * Double(options.fps)
        guard duration.isFinite, duration > 0, exactFrames.rounded() > 0 else {
            throw MotionError.invalidOptions("the animation has no finite duration. Define window.__hf = { duration, seek(t) }, or use finite CSS/WAAPI animations or a GSAP timeline in window.__timelines")
        }
        guard exactFrames.rounded() <= Double(Self.maxFrames) else {
            throw MotionError.invalidOptions("longer than \(Self.maxFrames / options.fps)s at \(options.fps) fps")
        }
        let frameCount = Int(exactFrames.rounded())

        try? FileManager.default.removeItem(at: url)
        let sink = try FrameSink(url: url, width: options.width, height: options.height, fps: options.fps)
        do {
            for index in 0..<frameCount {
                try Task.checkCancellation()
                // Quantized to the frame grid so preview and render ask for the same instants.
                let time = Double(index) / Double(options.fps)
                _ = try await run("await window.__hf.seek(t); return 0;", arguments: ["t": time], step: "seek(\(time))")
                let image = try await snapshot(width: options.width, height: options.height, index: index)
                try await sink.append(image, index: index)
            }
            try await sink.finish()
        } catch {
            await sink.cancel()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return MotionRenderResult(frameCount: frameCount, duration: Double(frameCount) / Double(options.fps))
    }

    // MARK: Page

    // Callback APIs on purpose: WebKit's async wrappers ignore cancellation and keep the view alive
    // while they wait, so a stuck page could not time out and its web process would outlive the render.

    private func load(_ html: String) async throws {
        try await Deadline<Void>().run(seconds: stepTimeout, step: "loading the page") { done in
            loader.onFinish = { error in
                done(error.map { .failure(MotionError.pageFailed($0.localizedDescription)) } ?? .success(()))
            }
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Runs `script`, which must return a value: WebKit's Swift overlay traps on an empty result.
    private func run(_ script: String, arguments: [String: Any] = [:], step: String) async throws -> Double? {
        try await Deadline<Double?>().run(seconds: stepTimeout, step: step) { done in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                done(result.map { ($0 as? NSNumber)?.doubleValue })
            }
        }
    }

    /// Installs the fallback adapters, waits for fonts and returns the page's duration.
    private func prepareSeekContract() async throws -> TimeInterval {
        _ = try? await run("await document.fonts.ready; return 0;", step: "loading fonts")
        _ = try await run(MotionAdapter.script + "\nreturn 0;", step: "installing the seek contract")
        // Not a JSON number when NaN or infinite, which comes back as an empty result.
        let duration = try await run("const d = Number(window.__hf.duration); return isFinite(d) ? d : 0;", step: "reading the duration")
        return duration ?? 0
    }

    private func snapshot(width: Int, height: Int, index: Int) async throws -> CGImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Points, not pixels: on a retina screen the full width would come back at 2x and be downscaled.
        configuration.snapshotWidth = NSNumber(value: Double(width) / window.backingScaleFactor)
        configuration.afterScreenUpdates = true
        return try await Deadline<CGImage>().run(seconds: stepTimeout, step: "painting frame \(index)") { done in
            webView.takeSnapshot(with: configuration) { image, _ in
                let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                done(cg.map { .success($0) } ?? .failure(MotionError.frameFailed(index)))
            }
        }
    }
}

// MARK: - Waiting on the page

/// Bridges one WebKit callback to async, giving up after `seconds`.
@MainActor
private final class Deadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timer: Task<Void, Error>?

    func run(seconds: TimeInterval, step: String,
             start: (@escaping @MainActor (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timer = Task { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.settle(.failure(MotionError.pageFailed("timed out after \(seconds)s \(step)")))
            }
            start { [self] in settle($0) }
        }
    }

    private func settle(_ result: Result<Value, Error>) {
        timer?.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    var onFinish: ((Error?) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish?(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinish?(error) }
}

// MARK: - Encoding

/// Appends frames to a HEVC-with-alpha movie, off the main actor so the editor stays responsive.
private actor FrameSink {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let fps: Int
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // Untagged video is read with a guessed matrix and the colors shift.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw MotionError.writerFailed("the movie rejected the video input") }
        writer.add(input)
        guard writer.startWriting() else { throw MotionError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage, index: Int) async throws {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 2_000_000)
            if writer.status == .failed { throw MotionError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
        }
        guard let pool = adaptor.pixelBufferPool else { throw MotionError.writerFailed("no pixel buffer pool") }
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess, let buffer = created else {
            throw MotionError.frameFailed(index)
        }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw MotionError.frameFailed(index) }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) else {
            throw MotionError.writerFailed(writer.error?.localizedDescription ?? "append failed at frame \(index)")
        }
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MotionError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
    }

    func cancel() { writer.cancelWriting() }
}
