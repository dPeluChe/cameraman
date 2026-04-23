//
//  MaskedVideoCompositor.swift
//  EngineKit
//
//  Custom AVVideoCompositing that applies shape masks to the camera PiP overlay.
//  Rendering helpers are in CompositorRenderers.swift and OverlayRenderer.swift.
//

@preconcurrency import AVFoundation
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
    let staticContent: StaticClipContent?

    public enum StaticClipContent {
        case image(path: String)
        case color(hexColor: String)
    }

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
        staticContent: StaticClipContent? = nil
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
        self.staticContent = staticContent
        super.init()

        var trackIDs: [NSValue] = [screenTrackID as NSValue]
        if let camID = cameraTrackID {
            trackIDs.append(camID as NSValue)
        }
        self.requiredSourceTrackIDs = trackIDs
    }
}

// MARK: - Custom Compositor

/// Compositor that renders screen + masked camera PiP
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
    var lastZoomLogSecond: Int = -1

    static let sharedRenderColorSpace = CGColorSpaceCreateDeviceRGB()

    /// Zoom plan for auto-zoom (set externally before playback)
    public static var activeZoomPlan: ZoomPlanGenerator.ZoomPlan?

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
        finalImage = compositeOverlays(over: finalImage, request: request, instruction: instruction, renderSize: renderSize)

        ciContext.render(finalImage, to: outputBuffer, bounds: canvasRect, colorSpace: Self.sharedRenderColorSpace)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    public func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Composition Pipeline

    private func buildScreenLayer(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize,
        canvasRect: CGRect
    ) -> CIImage {
        if instruction.screenMuted {
            return renderBackground(instruction: instruction, renderSize: renderSize)
        }

        if let staticContent = instruction.staticContent {
            return renderStaticContent(staticContent, renderSize: renderSize)
        }

        guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else {
            return renderBackground(instruction: instruction, renderSize: renderSize)
        }

        let rawScreen = CIImage(cvPixelBuffer: screenBuffer)
            .transformed(by: instruction.screenTransform)
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
        let cameraImage = CIImage(cvPixelBuffer: cameraBuffer).transformed(by: cameraTransform)
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
        guard let zoomPlan = MaskedVideoCompositor.activeZoomPlan else { return image }

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

    private func compositeOverlays(
        over image: CIImage,
        request: AVAsynchronousVideoCompositionRequest,
        instruction: MaskedVideoCompositionInstruction,
        renderSize: CGSize
    ) -> CIImage {
        let currentTime = request.compositionTime.seconds
        let activeOverlays = instruction.overlays.filter { currentTime >= $0.start && currentTime <= $0.end }
        guard !activeOverlays.isEmpty else { return image }

        let overlayKey = activeOverlays.map {
            "\($0.id)_\($0.x)_\($0.y)_\($0.scale)_\($0.rotation)_\($0.stroke)_\($0.strokeWidth)_\($0.shadow)_\($0.text ?? "")_\($0.fontSize ?? 0)_\($0.fontColor ?? "")_\($0.bgColor ?? "")"
        }.joined(separator: "|")

        let overlayLayer: CIImage
        cacheLock.lock()
        if overlayKey == cachedOverlayKey, let cached = cachedOverlayImage {
            overlayLayer = cached
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            let rendered = renderOverlayLayer(activeOverlays, renderSize: renderSize)
            cacheLock.lock()
            cachedOverlayImage = rendered
            cachedOverlayKey = overlayKey
            cacheLock.unlock()
            overlayLayer = rendered
        }

        return overlayLayer.composited(over: image)
    }
}
