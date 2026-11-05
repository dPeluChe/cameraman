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

    public init(width: Int = 1920, height: Int = 1080, fps: Int = 30, duration: TimeInterval? = nil) {
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration
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

    private init(width: Int, height: Int) {
        let configuration = WKWebViewConfiguration()
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
        let renderer = MotionRenderer(width: options.width, height: options.height)
        defer { renderer.close() }
        return try await renderer.render(html: html, to: url, options: options)
    }

    private func close() {
        webView.stopLoading()
        window.contentView = nil
        window.orderOut(nil)
    }

    private func render(html: String, to url: URL, options: MotionRenderOptions) async throws -> MotionRenderResult {
        try await loader.wait { webView.loadHTMLString(html, baseURL: nil) }
        let reported = try await prepareSeekContract()
        let duration = options.duration ?? reported
        let frameCount = Int((duration * Double(options.fps)).rounded())
        guard duration > 0, frameCount > 0 else {
            throw MotionError.invalidOptions("the animation has no duration. Define window.__hf = { duration, seek(t) }, or use finite CSS/WAAPI animations or a GSAP timeline in window.__timelines")
        }
        guard frameCount <= Self.maxFrames else { throw MotionError.invalidOptions("longer than \(Self.maxFrames / options.fps)s at \(options.fps) fps") }

        try? FileManager.default.removeItem(at: url)
        let sink = try FrameSink(url: url, width: options.width, height: options.height, fps: options.fps)
        do {
            for index in 0..<frameCount {
                // Quantized to the frame grid so preview and render ask for the same instants.
                let time = Double(index) / Double(options.fps)
                try await webView.callAsyncJavaScript("await window.__hf.seek(t);", arguments: ["t": time], contentWorld: .page)
                let image = try await snapshot(width: options.width, height: options.height, index: index)
                try await sink.append(image, index: index)
            }
            try await sink.finish()
        } catch {
            sink.cancel()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return MotionRenderResult(frameCount: frameCount, duration: Double(frameCount) / Double(options.fps))
    }

    // MARK: Page

    /// Installs the fallback adapters, waits for fonts and returns the page's duration.
    private func prepareSeekContract() async throws -> TimeInterval {
        _ = try? await webView.callAsyncJavaScript("await document.fonts.ready;", contentWorld: .page)
        _ = try await webView.callAsyncJavaScript(MotionAdapter.script, contentWorld: .page)
        let value = try await webView.callAsyncJavaScript("return Number(window.__hf.duration);", contentWorld: .page)
        return (value as? NSNumber)?.doubleValue ?? 0
    }

    private func snapshot(width: Int, height: Int, index: Int) async throws -> CGImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Points, not pixels: on a retina screen the full width would come back at 2x and be downscaled.
        configuration.snapshotWidth = NSNumber(value: Double(width) / window.backingScaleFactor)
        configuration.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: configuration)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw MotionError.frameFailed(index) }
        return cg
    }
}

// MARK: - Navigation

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(_ start: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            start()
        }
    }

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: MotionError.pageFailed(error.localizedDescription)) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}

// MARK: - Encoding

/// Appends frames to a HEVC-with-alpha movie.
@MainActor
private final class FrameSink {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let fps: Int

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
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
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw MotionError.frameFailed(index) }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
