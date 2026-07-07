//
//  MaskedVideoCompositor.swift
//  EngineKit
//
//  Custom AVVideoCompositing that applies shape masks to the camera PiP overlay.
//  Rendering helpers are in CompositorRenderers.swift and OverlayRenderer.swift.
//

@preconcurrency import AVFoundation
import AppKit
import CoreImage
import CoreGraphics

// MARK: - Overlay config (serializable for instruction)

/// Lightweight serializable overlay config passed to the compositor
public struct OverlayConfig: Codable, Sendable {
    public let id: String
    public let type: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let x: Double
    public let y: Double
    public let scale: Double
    public let rotation: Double
    public let stroke: String
    public let strokeWidth: Double
    public let shadow: Bool
    public let text: String?
    public let fontSize: Double?
    public let fontColor: String?
    public let bgColor: String?
    public let animationType: String?
    public let fadeInDuration: TimeInterval
    public let fadeOutDuration: TimeInterval
    /// Resolved absolute path to image asset (only set when type == .image).
    /// Compositor needs an absolute path because it has no access to the
    /// project directory at render time.
    public let imagePath: String?
    public let imageOpacity: Double

    public init(overlay: Project.Overlay) {
        self.id = overlay.id.uuidString
        self.type = overlay.type.rawValue
        self.start = overlay.start
        self.end = overlay.end
        self.x = overlay.transform.x
        self.y = overlay.transform.y
        self.scale = overlay.transform.scale
        self.rotation = overlay.transform.rotation
        self.stroke = overlay.style.stroke
        self.strokeWidth = overlay.style.strokeWidth
        self.shadow = overlay.style.shadow
        self.text = overlay.style.text
        self.fontSize = overlay.style.size
        self.fontColor = overlay.style.color
        self.bgColor = overlay.style.bg
        self.animationType = overlay.animation?.type.rawValue
        self.fadeInDuration = overlay.animation?.fadeInDuration ?? 0
        self.fadeOutDuration = overlay.animation?.fadeOutDuration ?? 0
        self.imagePath = overlay.style.imagePath
        self.imageOpacity = overlay.style.imageOpacity ?? 1.0
    }

    /// Compute the overlay's opacity at a given composition time. Honors the
    /// animation type (fadeIn / fadeOut / fadeInOut). Returns 0 outside the
    /// overlay's window. Pure function — safe to call per-frame.
    public func opacity(at time: TimeInterval) -> Double {
        guard time >= start && time <= end else { return 0 }
        guard let typeRaw = animationType,
              let type = Project.Overlay.Animation.AnimationType(rawValue: typeRaw),
              type != .none else { return 1 }

        let duration = end - start
        let localTime = time - start

        switch type {
        case .none:
            return 1
        case .fadeIn:
            guard fadeInDuration > 0 else { return 1 }
            return min(1, localTime / fadeInDuration)
        case .fadeOut:
            guard fadeOutDuration > 0 else { return 1 }
            let fadeStart = duration - fadeOutDuration
            if localTime < fadeStart { return 1 }
            return max(0, 1 - (localTime - fadeStart) / fadeOutDuration)
        case .fadeInOut:
            var alpha = 1.0
            if fadeInDuration > 0, localTime < fadeInDuration {
                alpha = localTime / fadeInDuration
            }
            if fadeOutDuration > 0 {
                let fadeStart = duration - fadeOutDuration
                if localTime > fadeStart {
                    alpha = min(alpha, max(0, 1 - (localTime - fadeStart) / fadeOutDuration))
                }
            }
            return alpha
        case .drawOn:
            // drawOn is animated geometrically, not via opacity — full visible
            return 1
        }
    }
}

// MARK: - Custom Instruction

/// Custom instruction that carries layout info for the compositor
public class MaskedVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    public var timeRange: CMTimeRange
    public var enablePostProcessing: Bool = false
    public var containsTweening: Bool = true
    public var requiredSourceTrackIDs: [NSValue]?
    public var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let renderSize: CGSize
    let screenTransform: CGAffineTransform
    let cameraTransform: CGAffineTransform?
    let cameraRect: CGRect?
    let maskShape: PiPMaskShape
    let cornerRadius: CGFloat
    let layoutType: String
    let screenMuted: Bool
    let videoCornerRadius: CGFloat
    let videoShadowIntensity: CGFloat
    let padding: CGFloat
    let backgroundType: String
    let backgroundValue: String
    let cameraBorderWidth: CGFloat
    let cameraBorderColor: String
    let overlays: [OverlayConfig]
    /// Visual effects to apply, filtered per-frame by target layer + time.
    /// Carried whole (like `overlays`/`zoomPlan`) and resolved at render time.
    let adjustments: [AdjustmentConfig]
    let staticContent: StaticClipContent?
    /// Effective zoom plan to apply for this instruction's time range.
    /// `nil` means no zoom. Already filtered by per-segment enabled state and
    /// gated by the player's `showZoom` toggle.
    let zoomPlan: ZoomPlanGenerator.ZoomPlan?
    /// Synthetic cursor path + click marks to draw on top of the frame.
    /// `nil` means no synthetic cursor (gated by `Project.SyntheticCursorConfig.enabled`).
    let cursorPlan: CursorPlan?
    let cursorConfig: Project.SyntheticCursorConfig?

    public enum StaticClipContent {
        case image(path: String)
        case color(hexColor: String)
    }

    /// An imported-video overlay source the compositor should composite above
    /// the screen/camera. Gaps in the track yield no source frame, so the
    /// overlay only shows while one of its clips is under the playhead.
    public struct VideoOverlaySource {
        /// Timeline window of one clip on this track, with its canvas placement.
        public struct ClipWindow {
            public let start: TimeInterval
            public let end: TimeInterval
            /// Normalized canvas rect (0-1, y from top). nil = fullscreen aspect-fit.
            public let position: CGRect?
            /// Per-clip visual effects (absolute-timeline windows) applied to the
            /// overlay image while this clip is active.
            public let adjustments: [AdjustmentConfig]

            public init(start: TimeInterval, end: TimeInterval, position: CGRect?, adjustments: [AdjustmentConfig] = []) {
                self.start = start
                self.end = end
                self.position = position
                self.adjustments = adjustments
            }
        }

        public let trackID: CMPersistentTrackID
        public let opacity: Double
        public let clipWindows: [ClipWindow]

        public init(trackID: CMPersistentTrackID, opacity: Double, clipWindows: [ClipWindow] = []) {
            self.trackID = trackID
            self.opacity = opacity
            self.clipWindows = clipWindows
        }

        private func window(at time: TimeInterval) -> ClipWindow? {
            clipWindows.first { time >= $0.start && time <= $0.end }
        }

        /// Placement for the clip active at `time` (nil = fullscreen aspect-fit).
        func position(at time: TimeInterval) -> CGRect? {
            window(at: time)?.position
        }

        /// Effects for the clip active at `time`.
        func adjustments(at time: TimeInterval) -> [AdjustmentConfig] {
            window(at: time)?.adjustments ?? []
        }
    }

    let videoOverlays: [VideoOverlaySource]

    init(
        timeRange: CMTimeRange,
        screenTrackID: CMPersistentTrackID,
        cameraTrackID: CMPersistentTrackID?,
        renderSize: CGSize,
        screenTransform: CGAffineTransform,
        cameraTransform: CGAffineTransform?,
        cameraRect: CGRect?,
        maskShape: PiPMaskShape,
        cornerRadius: CGFloat,
        layoutType: String,
        screenMuted: Bool = false,
        videoCornerRadius: CGFloat = 0,
        videoShadowIntensity: CGFloat = 0,
        padding: CGFloat = 0,
        backgroundType: String = "solid",
        backgroundValue: String = "#000000",
        cameraBorderWidth: CGFloat = 0,
        cameraBorderColor: String = "#FFFFFF",
        overlays: [OverlayConfig] = [],
        adjustments: [AdjustmentConfig] = [],
        staticContent: StaticClipContent? = nil,
        zoomPlan: ZoomPlanGenerator.ZoomPlan? = nil,
        videoOverlays: [VideoOverlaySource] = [],
        cursorPlan: CursorPlan? = nil,
        cursorConfig: Project.SyntheticCursorConfig? = nil
    ) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.renderSize = renderSize
        self.screenTransform = screenTransform
        self.cameraTransform = cameraTransform
        self.cameraRect = cameraRect
        self.maskShape = maskShape
        self.cornerRadius = cornerRadius
        self.layoutType = layoutType
        self.screenMuted = screenMuted
        self.videoCornerRadius = videoCornerRadius
        self.videoShadowIntensity = videoShadowIntensity
        self.padding = padding
        self.backgroundType = backgroundType
        self.backgroundValue = backgroundValue
        self.cameraBorderWidth = cameraBorderWidth
        self.cameraBorderColor = cameraBorderColor
        self.overlays = overlays
        self.adjustments = adjustments
        self.staticContent = staticContent
        self.zoomPlan = zoomPlan
        self.videoOverlays = videoOverlays
        self.cursorPlan = cursorPlan
        self.cursorConfig = cursorConfig
        super.init()

        // An invalid screenTrackID means "no recording on the primary track"
        // (empty projects) — requiring a media-less track invalidates the whole
        // videoComposition with AVError -11800.
        var trackIDs: [NSValue] = []
        if screenTrackID != kCMPersistentTrackID_Invalid {
            trackIDs.append(screenTrackID as NSValue)
        }
        if let camID = cameraTrackID {
            trackIDs.append(camID as NSValue)
        }
        trackIDs.append(contentsOf: videoOverlays.map { $0.trackID as NSValue })
        self.requiredSourceTrackIDs = trackIDs
    }
}

// MARK: - Custom Compositor

/// Compositor that renders screen + masked camera PiP.
///
/// Note: the two pixel-buffer-attribute properties below trigger a Swift 6
/// "sendability of function types" warning because AVVideoCompositing
/// annotates them NS_SWIFT_SENDABLE on the ObjC side but Swift can't synthesize
/// a `@Sendable` getter for `[String: Any]` storage. None of the standard
/// workarounds (`@preconcurrency import`, `@preconcurrency` on the conformance,
/// `nonisolated` computed property, swapping to `[String: any Sendable]`) clear
/// the warning — it's an SDK/compiler interaction that needs an Apple fix.
/// Keeping the original form pending Swift 6 mode adoption.
public class MaskedVideoCompositor: NSObject, AVVideoCompositing {
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) public let sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) public let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    private var renderContext: AVVideoCompositionRenderContext?
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    let cacheLock = NSLock()

    var cachedBorderImage: CIImage?
    var cachedBorderKey: String?
    var cachedOverlayImage: CIImage?
    var cachedOverlayKey: String?
    var cachedStaticImages: [String: CIImage] = [:]
    /// Loaded NSImages for image-overlays, keyed by absolute path. Avoids
    /// re-reading the asset off disk on every frame. Bounded so long-running
    /// previews with many distinct image overlays don't grow unbounded.
    var cachedOverlayAssets: [String: NSImage] = [:]
    var cachedOverlayAssetOrder: [String] = []  // LRU access order
    static let maxCachedAssets = 16
    /// Pre-computed per-frame durations for GIFs, keyed by absolute path.
    /// `setProperty(.currentFrame) + read(.currentFrameDuration)` is slow on
    /// NSBitmapImageRep; we did it on every gifFrame call. Now it's per-asset.
    var cachedGifDurations: [String: [TimeInterval]] = [:]
    var lastZoomLogSecond: Int = -1

    static let sharedRenderColorSpace = CGColorSpaceCreateDeviceRGB()

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? MaskedVideoCompositionInstruction else {
            request.finish(with: NSError(domain: "MaskedVideoCompositor", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid instruction type"]))
            return
        }

        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MaskedVideoCompositor", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]))
            return
        }

        let renderSize = instruction.renderSize
        let canvasRect = CGRect(origin: .zero, size: renderSize)

        var finalImage = buildScreenLayer(request: request, instruction: instruction, renderSize: renderSize, canvasRect: canvasRect)
        finalImage = compositeCamera(over: finalImage, request: request, instruction: instruction, renderSize: renderSize)
        finalImage = applyZoom(to: finalImage, request: request, instruction: instruction, renderSize: renderSize)
        finalImage = compositeVideoOverlays(over: finalImage, request: request, instruction: instruction, renderSize: renderSize)
        // Frame-wide effects apply to the fully composited image (screen + camera
        // + overlays), before annotation overlays so text/arrows stay crisp.
        finalImage = applyAdjustments(.frame, to: finalImage, request: request, instruction: instruction, extent: canvasRect)
        finalImage = compositeOverlays(over: finalImage, request: request, instruction: instruction, renderSize: renderSize)
        finalImage = compositeCursor(over: finalImage, request: request, instruction: instruction, renderSize: renderSize)

        ciContext.render(finalImage, to: outputBuffer, bounds: canvasRect, colorSpace: Self.sharedRenderColorSpace)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    public func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Effects

    /// Apply the instruction's effects for one layer at the current frame time.
    /// No-op when the instruction carries no adjustments for that target.
    func applyAdjustments(
        _ target: Project.AdjustmentTarget,
        to image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        extent: CGRect
    ) -> CIImage {
        guard !instruction.adjustments.isEmpty else { return image }
        return AdjustmentRenderer.apply(
            instruction.adjustments,
            target: target,
            to: image,
            at: request.compositionTime.seconds,
            extent: extent
        )
    }

    // MARK: - Composition Pipeline

    private func buildScreenLayer(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize,
        canvasRect: CGRect
    ) -> CIImage {
        if instruction.screenMuted {
            let bg = renderBackground(instruction: instruction, renderSize: renderSize)
            return applyAdjustments(.background, to: bg, request: request, instruction: instruction, extent: canvasRect)
        }

        if let staticContent = instruction.staticContent {
            // Static image/color is the "screen" content for this clip.
            let content = renderStaticContent(staticContent, renderSize: renderSize)
            return applyAdjustments(.screen, to: content, request: request, instruction: instruction, extent: canvasRect)
        }

        guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else {
            return renderBackground(instruction: instruction, renderSize: renderSize)
        }

        // The static screenTransform was computed for one source resolution, but a
        // merged project's track can switch resolutions mid-timeline (clips from
        // different displays). If this frame doesn't fill the canvas under the
        // static transform, refit it aspect-fit centered.
        let sourceImage = CIImage(cvPixelBuffer: screenBuffer)
        let staticExtent = sourceImage.extent.applying(instruction.screenTransform)
        let effectiveTransform: CGAffineTransform
        if abs(staticExtent.width - renderSize.width) < 2 || abs(staticExtent.height - renderSize.height) < 2 {
            effectiveTransform = instruction.screenTransform
        } else {
            let extent = sourceImage.extent
            let scale = min(renderSize.width / extent.width, renderSize.height / extent.height)
            effectiveTransform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: (renderSize.width - extent.width * scale) / 2 - extent.minX * scale,
                ty: (renderSize.height - extent.height * scale) / 2 - extent.minY * scale
            )
        }

        let rawScreen = sourceImage
            .transformed(by: effectiveTransform)
            .cropped(to: canvasRect)

        var background: CIImage
        if instruction.backgroundType == "blur" {
            let blurRadius = Double(instruction.backgroundValue) ?? 10
            background = rawScreen.clampedToExtent()
                .applyingGaussianBlur(sigma: blurRadius)
                .cropped(to: canvasRect)
        } else {
            background = renderBackground(instruction: instruction, renderSize: renderSize)
        }

        var screenImage = rawScreen
        let pad = instruction.padding
        if pad > 0.001 {
            let scale = 1.0 - pad
            let offsetX = (renderSize.width * pad) / 2
            let offsetY = (renderSize.height * pad) / 2
            screenImage = screenImage
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
                .cropped(to: canvasRect)
        }

        if instruction.videoCornerRadius > 0 {
            screenImage = applyCornerRadius(to: screenImage, radius: instruction.videoCornerRadius, renderSize: renderSize, padding: pad)
        }

        // Per-layer effects: e.g. sepia the screen while the background goes B&W.
        background = applyAdjustments(.background, to: background, request: request, instruction: instruction, extent: canvasRect)
        screenImage = applyAdjustments(.screen, to: screenImage, request: request, instruction: instruction, extent: canvasRect)

        return screenImage.composited(over: background)
    }

    private func compositeCamera(
        over finalImage: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        guard let camTrackID = instruction.cameraTrackID,
              let cameraBuffer = request.sourceFrame(byTrackID: camTrackID),
              let cameraTransform = instruction.cameraTransform else {
            return finalImage
        }

        var result = finalImage
        let rawCamera = CIImage(cvPixelBuffer: cameraBuffer)

        // Same mixed-resolution guard as the screen layer: the static transform
        // was computed for one camera resolution; if this frame lands outside its
        // intended PiP rect (known via cameraRect), refit it aspect-fit centered.
        var effectiveCameraTransform = cameraTransform
        if let normalizedRect = instruction.cameraRect {
            let target = CGRect(
                x: normalizedRect.minX * renderSize.width,
                y: (1.0 - normalizedRect.minY - normalizedRect.height) * renderSize.height,
                width: normalizedRect.width * renderSize.width,
                height: normalizedRect.height * renderSize.height
            )
            let staticExtent = rawCamera.extent.applying(cameraTransform)
            if abs(staticExtent.width - target.width) > 2 && abs(staticExtent.height - target.height) > 2 {
                let extent = rawCamera.extent
                let scale = min(target.width / extent.width, target.height / extent.height)
                effectiveCameraTransform = CGAffineTransform(
                    a: scale, b: 0, c: 0, d: scale,
                    tx: target.minX + (target.width - extent.width * scale) / 2 - extent.minX * scale,
                    ty: target.minY + (target.height - extent.height * scale) / 2 - extent.minY * scale
                )
            }
        }

        var cameraImage = rawCamera.transformed(by: effectiveCameraTransform)
        // Camera-layer effects (e.g. sepia camera) applied before masking so the
        // mask/border frame the filtered image.
        cameraImage = applyAdjustments(.camera, to: cameraImage, request: request, instruction: instruction, extent: cameraImage.extent)
        let camExtent = cameraImage.extent.intersection(CGRect(origin: .zero, size: renderSize))

        if instruction.maskShape != .none && !camExtent.isEmpty {
            let maskedCamera = applyMask(to: cameraImage, shape: instruction.maskShape, rect: camExtent, cornerRadius: instruction.cornerRadius, renderSize: renderSize)
            result = maskedCamera.composited(over: result)
        } else {
            result = cameraImage.cropped(to: CGRect(origin: .zero, size: renderSize)).composited(over: result)
        }

        if instruction.cameraBorderWidth > 0 && !camExtent.isEmpty {
            let borderShape = instruction.maskShape == .none ? PiPMaskShape.roundedRect : instruction.maskShape
            let borderRadius = instruction.maskShape == .none ? CGFloat(0) : instruction.cornerRadius
            let key = "\(borderShape)_\(camExtent)_\(borderRadius)_\(instruction.cameraBorderWidth)_\(instruction.cameraBorderColor)_\(renderSize)"

            cacheLock.lock()
            if key == cachedBorderKey, let cached = cachedBorderImage {
                cacheLock.unlock()
                result = cached.composited(over: result)
            } else {
                cacheLock.unlock()
                let rendered = renderCameraBorder(shape: borderShape, rect: camExtent, cornerRadius: borderRadius, borderWidth: instruction.cameraBorderWidth, borderColor: instruction.cameraBorderColor, renderSize: renderSize)
                cacheLock.lock()
                cachedBorderImage = rendered
                cachedBorderKey = key
                cacheLock.unlock()
                result = rendered.composited(over: result)
            }
        }

        return result
    }

    private func applyZoom(
        to image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        guard let zoomPlan = instruction.zoomPlan else { return image }

        let time = request.compositionTime.seconds
        let zoomLevel = zoomPlan.zoomLevel(at: time)
        guard zoomLevel > 1.001 else { return image }

        let focusPoint = zoomPlan.focusPoint(at: time)
        let canvasRect = CGRect(origin: .zero, size: renderSize)
        let scale = CGFloat(zoomLevel)

        let t = instruction.screenTransform
        let srcW = (t.a > 0) ? renderSize.width / t.a : renderSize.width
        let srcH = (t.d > 0) ? renderSize.height / t.d : renderSize.height
        let rawX = CGFloat(focusPoint.x) * srcW
        // NSEvent Cocoa coords: y=0 at visual BOTTOM (same as CIImage mathematical space).
        // No flip needed — contrast with OverlayRenderer which flips view-space y=0-at-top coords.
        let rawY = CGFloat(focusPoint.y) * srcH
        let focusX = rawX * t.a + t.tx
        let focusY = rawY * t.d + t.ty
        let tx = focusX - focusX * scale
        let ty = focusY - focusY * scale

#if DEBUG
        let logKey = Int(time)
        if logKey != lastZoomLogSecond {
            lastZoomLogSecond = logKey
            LogDebug(.preview, "applyZoom t=\(String(format: "%.2f", time)) level=\(String(format: "%.2f", zoomLevel)) rawFocus=(\(String(format: "%.3f", focusPoint.x)),\(String(format: "%.3f", focusPoint.y))) canvasFocus=(\(Int(focusX)),\(Int(focusY))) renderSize=\(Int(renderSize.width))x\(Int(renderSize.height))")
        }
#endif

        return image
            .transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty))
            .cropped(to: canvasRect)
    }

    /// Composite imported-video overlay frames (B-roll) above the zoomed
    /// screen/camera, aspect-fit centered, honoring track opacity. Tracks with
    /// no media at this time yield no source frame and are skipped.
    private func compositeVideoOverlays(
        over image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        guard !instruction.videoOverlays.isEmpty else { return image }

        var result = image
        let canvasRect = CGRect(origin: .zero, size: renderSize)
        let time = request.compositionTime.seconds

        for source in instruction.videoOverlays {
            guard let buffer = request.sourceFrame(byTrackID: source.trackID) else { continue }

            var overlayImage = CIImage(cvPixelBuffer: buffer)
            let extent = overlayImage.extent
            guard extent.width > 0, extent.height > 0 else { continue }

            // Target rect: the active clip's normalized placement (y from top,
            // flipped into CI bottom-up space) or the full canvas.
            let targetRect: CGRect
            if let pos = source.position(at: time) {
                targetRect = CGRect(
                    x: pos.origin.x * renderSize.width,
                    y: (1.0 - pos.origin.y - pos.height) * renderSize.height,
                    width: pos.width * renderSize.width,
                    height: pos.height * renderSize.height
                )
            } else {
                targetRect = canvasRect
            }

            // Aspect-fit into the target rect, centered
            let scale = min(targetRect.width / extent.width, targetRect.height / extent.height)
            let tx = targetRect.minX + (targetRect.width - extent.width * scale) / 2 - extent.origin.x * scale
            let ty = targetRect.minY + (targetRect.height - extent.height * scale) / 2 - extent.origin.y * scale
            overlayImage = overlayImage
                .transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty))
                .cropped(to: canvasRect)

            // Per-clip effects (sepia, B&W, brightness, blur…) on the overlay itself.
            let clipAdjustments = source.adjustments(at: time)
            if !clipAdjustments.isEmpty {
                overlayImage = AdjustmentRenderer.applyClip(clipAdjustments, to: overlayImage, at: time, extent: canvasRect)
            }

            if source.opacity < 0.999 {
                overlayImage = overlayImage.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(source.opacity))
                ])
            }

            result = overlayImage.composited(over: result)
        }

        return result
    }

    private func compositeOverlays(
        over image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        let currentTime = request.compositionTime.seconds
        let activeOverlays = instruction.overlays.filter { currentTime >= $0.start && currentTime <= $0.end }
        guard !activeOverlays.isEmpty else { return image }

        // Pair each active overlay with its computed opacity at this frame.
        // Opacity is quantized to 0.05 buckets in the cache key so the cache
        // invalidates ~20 times per fade (smooth enough, cheap enough).
        let withOpacity: [(OverlayConfig, Double)] = activeOverlays.map { ($0, $0.opacity(at: currentTime)) }
        // Skip rendering entirely if every active overlay is fully transparent.
        guard withOpacity.contains(where: { $0.1 > 0.01 }) else { return image }

        let overlayKey = withOpacity.map { config, opacity in
            let opacityBucket = Int(opacity * 20)  // 0..20
            return "\(config.id)_\(config.type)_\(config.x)_\(config.y)_\(config.scale)_\(config.rotation)_\(config.stroke)_\(config.strokeWidth)_\(config.shadow)_\(config.text ?? "")_\(config.fontSize ?? 0)_\(config.fontColor ?? "")_\(config.bgColor ?? "")_\(config.imagePath ?? "")_\(config.imageOpacity)_\(opacityBucket)"
        }.joined(separator: "|")

        let overlayLayer: CIImage
        cacheLock.lock()
        if overlayKey == cachedOverlayKey, let cached = cachedOverlayImage {
            overlayLayer = cached
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            let rendered = renderOverlayLayer(withOpacity, currentTime: currentTime, renderSize: renderSize)
            cacheLock.lock()
            cachedOverlayImage = rendered
            cachedOverlayKey = overlayKey
            cacheLock.unlock()
            overlayLayer = rendered
        }

        return overlayLayer.composited(over: image)
    }
}
