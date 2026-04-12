//
//  MaskedVideoCompositor.swift
//  EngineKit
//
//  Custom AVVideoCompositing that applies shape masks to the camera PiP overlay.
//  Supports circle, rounded rectangle, and other mask shapes.
//

import AVFoundation
import CoreImage
import CoreGraphics

// MARK: - Overlay config (serializable for instruction)

/// Lightweight serializable overlay config passed to the compositor
public struct OverlayConfig: Codable, Sendable {
    public let id: String
    public let type: String // "arrow", "rect", "line", "text"
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

    // Layout info
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let renderSize: CGSize
    let screenTransform: CGAffineTransform
    let cameraTransform: CGAffineTransform?
    let cameraRect: CGRect?  // Normalized camera rect (0-1)
    let maskShape: PiPMaskShape
    let cornerRadius: CGFloat
    let layoutType: String
    let screenMuted: Bool

    // Visual effects
    let videoCornerRadius: CGFloat
    let videoShadowIntensity: CGFloat
    let padding: CGFloat
    let backgroundType: String
    let backgroundValue: String

    // Camera border
    let cameraBorderWidth: CGFloat
    let cameraBorderColor: String

    // Overlays
    let overlays: [OverlayConfig]

    // Static content for non-recording clips (image path or hex color)
    let staticContent: StaticClipContent?

    /// Describes static content to render when there's no video source
    public enum StaticClipContent {
        /// Render a static image from disk
        case image(path: String)
        /// Render a solid color fill
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
    nonisolated(unsafe) public let sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    nonisolated(unsafe) public let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let cacheLock = NSLock()

    // Border cache — avoid CGContext allocation per frame
    private var cachedBorderImage: CIImage?
    private var cachedBorderKey: String?

    // Overlay cache — avoid CGContext allocation per frame for static overlays
    private var cachedOverlayImage: CIImage?
    private var cachedOverlayKey: String?

    // Static image cache — loaded once, reused across frames
    private var cachedStaticImages: [String: CIImage] = [:]

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

        // Screen content
        var finalImage: CIImage
        if instruction.screenMuted {
            finalImage = renderBackground(instruction: instruction, renderSize: renderSize)
        } else if let staticContent = instruction.staticContent {
            // Static clip: render image or color instead of video
            finalImage = renderStaticContent(staticContent, renderSize: renderSize)
        } else {
            guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else {
                // No video data — render background as fallback
                finalImage = renderBackground(instruction: instruction, renderSize: renderSize)
                ciContext.render(finalImage, to: outputBuffer,
                    bounds: CGRect(origin: .zero, size: renderSize),
                    colorSpace: CGColorSpaceCreateDeviceRGB())
                request.finish(withComposedVideoFrame: outputBuffer)
                return
            }
            let rawScreen = CIImage(cvPixelBuffer: screenBuffer)
                .transformed(by: instruction.screenTransform)
                .cropped(to: canvasRect)

            // Background: blurred screen or solid/gradient
            if instruction.backgroundType == "blur" {
                let blurRadius = Double(instruction.backgroundValue) ?? 10
                finalImage = rawScreen.clampedToExtent()
                    .applyingGaussianBlur(sigma: blurRadius)
                    .cropped(to: canvasRect)
            } else {
                finalImage = renderBackground(instruction: instruction, renderSize: renderSize)
            }

            // Apply padding (scale down and center)
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

            // Apply corner radius
            if instruction.videoCornerRadius > 0 {
                screenImage = applyCornerRadius(to: screenImage, radius: instruction.videoCornerRadius, renderSize: renderSize, padding: pad)
            }

            finalImage = screenImage.composited(over: finalImage)
        }

        // Add camera if available
        if let camTrackID = instruction.cameraTrackID,
           let cameraBuffer = request.sourceFrame(byTrackID: camTrackID),
           let cameraTransform = instruction.cameraTransform {

            let cameraImage = CIImage(cvPixelBuffer: cameraBuffer)
                .transformed(by: cameraTransform)

            // Get the actual extent of the transformed camera image
            let camExtent = cameraImage.extent.intersection(CGRect(origin: .zero, size: renderSize))

            // Apply mask to camera (skip for .none — just crop)
            if instruction.maskShape != .none && !camExtent.isEmpty {
                let maskedCamera = applyMask(
                    to: cameraImage,
                    shape: instruction.maskShape,
                    rect: camExtent,
                    cornerRadius: instruction.cornerRadius,
                    renderSize: renderSize
                )
                finalImage = maskedCamera.composited(over: finalImage)
            } else {
                let croppedCamera = cameraImage.cropped(to: CGRect(origin: .zero, size: renderSize))
                finalImage = croppedCamera.composited(over: finalImage)
            }

            // Draw border around camera (all shapes including .none = rectangle)
            if instruction.cameraBorderWidth > 0 && !camExtent.isEmpty {
                let borderShape = instruction.maskShape == .none ? PiPMaskShape.roundedRect : instruction.maskShape
                let borderRadius = instruction.maskShape == .none ? CGFloat(0) : instruction.cornerRadius
                let key = "\(borderShape)_\(camExtent)_\(borderRadius)_\(instruction.cameraBorderWidth)_\(instruction.cameraBorderColor)_\(renderSize)"
                let borderImage: CIImage
                cacheLock.lock()
                if key == cachedBorderKey, let cached = cachedBorderImage {
                    borderImage = cached
                    cacheLock.unlock()
                } else {
                    cacheLock.unlock()
                    let rendered = renderCameraBorder(
                        shape: borderShape, rect: camExtent, cornerRadius: borderRadius,
                        borderWidth: instruction.cameraBorderWidth, borderColor: instruction.cameraBorderColor,
                        renderSize: renderSize
                    )
                    cacheLock.lock()
                    cachedBorderImage = rendered
                    cachedBorderKey = key
                    cacheLock.unlock()
                    borderImage = rendered
                }
                finalImage = borderImage.composited(over: finalImage)
            }
        }

        // Apply zoom if active
        if let zoomPlan = MaskedVideoCompositor.activeZoomPlan {
            let time = request.compositionTime.seconds
            let zoomLevel = zoomPlan.zoomLevel(at: time)
            if zoomLevel > 1.001 {
                let focusPoint = zoomPlan.focusPoint(at: time)
                let canvasRect = CGRect(origin: .zero, size: renderSize)
                let scale = CGFloat(zoomLevel)
                // Focus point is normalized (0-1) in screen-source space (top-down Y).
                // Apply screenTransform to map into canvas space (CIImage bottom-up Y).
                let t = instruction.screenTransform
                let srcW = (t.a > 0) ? renderSize.width / t.a : renderSize.width
                let srcH = (t.d > 0) ? renderSize.height / t.d : renderSize.height
                let rawX = CGFloat(focusPoint.x) * srcW
                let rawY = (1.0 - CGFloat(focusPoint.y)) * srcH
                let focusX = rawX * t.a + t.tx
                let focusY = rawY * t.d + t.ty
                let tx = focusX - focusX * scale
                let ty = focusY - focusY * scale
                finalImage = finalImage
                    .transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty))
                    .cropped(to: canvasRect)
            }
        }

        // Render overlays if any are active at this time
        let currentTime = request.compositionTime.seconds
        let activeOverlays = instruction.overlays.filter { overlay in
            currentTime >= overlay.start && currentTime <= overlay.end
        }
        if !activeOverlays.isEmpty {
            let overlayKey = activeOverlays.map {
                "\($0.id)_\($0.x)_\($0.y)_\($0.scale)_\($0.rotation)_\($0.stroke)"
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
            finalImage = overlayLayer.composited(over: finalImage)
        }

        // Render to output buffer
        ciContext.render(
            finalImage,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    public func cancelAllPendingVideoCompositionRequests() {
        // No-op for synchronous rendering
    }

    // MARK: - Mask Application

    private func applyMask(
        to image: CIImage,
        shape: PiPMaskShape,
        rect: CGRect,
        cornerRadius: CGFloat,
        renderSize: CGSize
    ) -> CIImage {
        // Create mask path
        let maskPath: CGPath
        switch shape {
        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            maskPath = CGPath(ellipseIn: circleRect, transform: nil)

        case .roundedRect:
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            maskPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            maskPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        case .none:
            return image
        }

        // Render mask to CGImage
        let maskSize = renderSize
        guard let maskContext = CGContext(
            data: nil,
            width: Int(maskSize.width),
            height: Int(maskSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(maskSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }

        // Draw mask (white = visible, black = hidden)
        maskContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        maskContext.fill(CGRect(origin: .zero, size: maskSize))
        maskContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        maskContext.addPath(maskPath)
        maskContext.fillPath()

        guard let maskCGImage = maskContext.makeImage() else {
            return image
        }

        let maskCIImage = CIImage(cgImage: maskCGImage)

        // Apply mask using CIBlendWithMask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return image
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: maskSize)), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    // MARK: - Static Content Rendering

    /// Render a static image or solid color to fill the canvas
    private func renderStaticContent(_ content: MaskedVideoCompositionInstruction.StaticClipContent, renderSize: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: renderSize)

        switch content {
        case .image(let path):
            // Check cache first
            cacheLock.lock()
            if let cached = cachedStaticImages[path] {
                cacheLock.unlock()
                return fitImageToCanvas(cached, renderSize: renderSize)
            }
            cacheLock.unlock()

            // Load image from disk
            guard let cgImage = loadCGImage(from: path) else {
                return CIImage(color: .black).cropped(to: canvasRect)
            }
            let ciImage = CIImage(cgImage: cgImage)

            cacheLock.lock()
            cachedStaticImages[path] = ciImage
            cacheLock.unlock()

            return fitImageToCanvas(ciImage, renderSize: renderSize)

        case .color(let hexColor):
            let color = ciColor(from: hexColor)
            return CIImage(color: color).cropped(to: canvasRect)
        }
    }

    /// Fit an image to the canvas size maintaining aspect ratio (letterbox)
    private func fitImageToCanvas(_ image: CIImage, renderSize: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: renderSize)
        let imageExtent = image.extent

        guard imageExtent.width > 0 && imageExtent.height > 0 else {
            return CIImage(color: .black).cropped(to: canvasRect)
        }

        let scaleX = renderSize.width / imageExtent.width
        let scaleY = renderSize.height / imageExtent.height
        let scale = min(scaleX, scaleY) // Fit (letterbox)

        let scaledW = imageExtent.width * scale
        let scaledH = imageExtent.height * scale
        let offsetX = (renderSize.width - scaledW) / 2
        let offsetY = (renderSize.height - scaledH) / 2

        // Background (black) + scaled image centered
        let background = CIImage(color: .black).cropped(to: canvasRect)
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: canvasRect)

        return scaled.composited(over: background)
    }

    /// Load a CGImage from an absolute file path
    private func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else { return nil }

        let ext = url.pathExtension.lowercased()
        if ext == "png" {
            return CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        } else {
            return CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    // MARK: - Background Rendering

    private func renderBackground(instruction: MaskedVideoCompositionInstruction, renderSize: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: renderSize)

        switch instruction.backgroundType {
        case "gradient":
            return renderGradientBackground(value: instruction.backgroundValue, size: renderSize)
        case "solid":
            let color = ciColor(from: instruction.backgroundValue)
            return CIImage(color: color).cropped(to: rect)
        default:
            return CIImage(color: .black).cropped(to: rect)
        }
    }

    private func renderGradientBackground(value: String, size: CGSize) -> CIImage {
        let parts = value.split(separator: ",")
        guard parts.count >= 2 else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }

        let startColor = ciColor(from: String(parts[0]))
        let endColor = ciColor(from: String(parts[1]))

        guard let gradient = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: startColor).cropped(to: CGRect(origin: .zero, size: size))
        }

        gradient.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint0")
        gradient.setValue(startColor, forKey: "inputColor0")
        gradient.setValue(CIVector(x: size.width, y: 0), forKey: "inputPoint1")
        gradient.setValue(endColor, forKey: "inputColor1")

        return (gradient.outputImage ?? CIImage(color: startColor))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func ciColor(from hex: String) -> CIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return .black
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return CIColor(red: r, green: g, blue: b)
    }

    // MARK: - Video Effects

    private func applyCornerRadius(to image: CIImage, radius: CGFloat, renderSize: CGSize, padding: CGFloat) -> CIImage {
        let scale = 1.0 - padding
        let insetW = renderSize.width * scale
        let insetH = renderSize.height * scale
        let offsetX = (renderSize.width - insetW) / 2
        let offsetY = (renderSize.height - insetH) / 2
        let videoRect = CGRect(x: offsetX, y: offsetY, width: insetW, height: insetH)

        let maskPath = CGPath(roundedRect: videoRect,
                              cornerWidth: radius, cornerHeight: radius,
                              transform: nil)

        guard let ctx = CGContext(
            data: nil, width: Int(renderSize.width), height: Int(renderSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(renderSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: renderSize))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(maskPath)
        ctx.fillPath()

        guard let maskCG = ctx.makeImage() else { return image }

        let maskCI = CIImage(cgImage: maskCG)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize)),
                       forKey: kCIInputBackgroundImageKey)
        blend.setValue(maskCI, forKey: kCIInputMaskImageKey)

        return blend.outputImage ?? image
    }

    // MARK: - Camera Border

    private func renderCameraBorder(
        shape: PiPMaskShape,
        rect: CGRect,
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        borderColor: String,
        renderSize: CGSize
    ) -> CIImage {
        let borderPath: CGPath
        switch shape {
        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            borderPath = CGPath(ellipseIn: circleRect, transform: nil)
        case .roundedRect:
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            borderPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            borderPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .none:
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        }

        guard let ctx = CGContext(
            data: nil, width: Int(renderSize.width), height: Int(renderSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(renderSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        }

        ctx.clear(CGRect(origin: .zero, size: renderSize))

        let color = cgColor(from: borderColor)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(borderWidth)
        ctx.addPath(borderPath)
        ctx.strokePath()

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        }
        return CIImage(cgImage: cgImage)
    }

    private func cgColor(from hex: String) -> CGColor {
        let ci = ciColor(from: hex)
        return CGColor(red: ci.red, green: ci.green, blue: ci.blue, alpha: ci.alpha)
    }

    // MARK: - Overlay Rendering

    /// Render overlay shapes to a transparent CIImage layer (cacheable)
    private func renderOverlayLayer(_ overlays: [OverlayConfig], renderSize: CGSize) -> CIImage {
        let clearImage = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        guard let ctx = CGContext(
            data: nil, width: Int(renderSize.width), height: Int(renderSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(renderSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return clearImage
        }

        ctx.clear(CGRect(origin: .zero, size: renderSize))

        for overlay in overlays {
            renderOverlay(overlay, in: ctx, renderSize: renderSize)
        }

        guard let cgImage = ctx.makeImage() else { return clearImage }
        return CIImage(cgImage: cgImage)
    }

    private func renderOverlay(_ overlay: OverlayConfig, in ctx: CGContext, renderSize: CGSize) {
        let overlayType = Project.Overlay.OverlayType(rawValue: overlay.type) ?? .rect
        let baseSize = OverlayBaseSize.size(for: overlayType, canvasSize: renderSize)

        let scaledW = baseSize.width * overlay.scale
        let scaledH = baseSize.height * overlay.scale
        let cx = overlay.x * renderSize.width
        // Y is top-down normalized, CGContext origin is bottom-left
        let cy = (1.0 - overlay.y) * renderSize.height

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: overlay.rotation * .pi / 180.0)

        if overlay.shadow {
            ctx.setShadow(offset: CGSize(width: 4, height: 4), blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        }

        let color = cgColor(from: overlay.stroke)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(overlay.strokeWidth)

        switch overlayType {
        case .arrow:
            renderArrowShape(in: ctx, size: CGSize(width: scaledW, height: scaledH), color: color, strokeWidth: overlay.strokeWidth)
        case .rect:
            renderRectShape(in: ctx, size: CGSize(width: scaledW, height: scaledH), color: color, strokeWidth: overlay.strokeWidth, bgColor: overlay.bgColor)
        case .line:
            renderLineShape(in: ctx, size: CGSize(width: scaledW, height: scaledH), color: color, strokeWidth: overlay.strokeWidth)
        case .text:
            renderTextShape(in: ctx, size: CGSize(width: scaledW, height: scaledH), text: overlay.text ?? "Text", fontSize: overlay.fontSize ?? 24, fontColor: overlay.fontColor ?? "#FFFFFF", bgColor: overlay.bgColor)
        }

        ctx.restoreGState()
    }

    private func renderArrowShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double) {
        let path = CGMutablePath()
        let shaftW = size.width * 0.7
        let shaftH = size.height * 0.2
        let headH = size.height * 0.8

        path.move(to: CGPoint(x: -size.width / 2, y: -shaftH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: -shaftH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: -headH / 2))
        path.addLine(to: CGPoint(x: size.width / 2, y: 0))
        path.addLine(to: CGPoint(x: shaftW / 2, y: headH / 2))
        path.addLine(to: CGPoint(x: shaftW / 2, y: shaftH / 2))
        path.addLine(to: CGPoint(x: -size.width / 2, y: shaftH / 2))
        path.closeSubpath()

        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func renderRectShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double, bgColor: String?) {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let radius: CGFloat = 10

        if let bg = bgColor {
            ctx.setFillColor(cgColor(from: bg))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }

        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    private func renderLineShape(in ctx: CGContext, size: CGSize, color: CGColor, strokeWidth: Double) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.move(to: CGPoint(x: -size.width / 2, y: 0))
        ctx.addLine(to: CGPoint(x: size.width / 2, y: 0))
        ctx.strokePath()
    }

    private func renderTextShape(in ctx: CGContext, size: CGSize, text: String, fontSize: Double, fontColor: String, bgColor: String?) {
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

        if let bg = bgColor {
            ctx.setFillColor(cgColor(from: bg))
            ctx.fill(rect)
        }

        // Render text to a separate context to avoid Y-axis issues with CoreText
        let textSize = CGSize(width: size.width, height: size.height)
        guard let textCtx = CGContext(
            data: nil, width: Int(textSize.width), height: Int(textSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(textSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        textCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        textCtx.fill(CGRect(origin: .zero, size: textSize))

        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let color = cgColor(from: fontColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Flip Y for CoreText (expects Y-up)
        textCtx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        textCtx.textPosition = CGPoint(x: (textSize.width - bounds.width) / 2, y: -((textSize.height - bounds.height) / 2 + bounds.height * 0.25))
        CTLineDraw(line, textCtx)

        guard let textImage = textCtx.makeImage() else { return }
        let textCI = CIImage(cgImage: textImage)

        // Composite onto main context at the overlay position
        // We need to draw this into the main context, but we're in a CGContext, not CIImage pipeline
        // So we draw directly
        ctx.saveGState()
        ctx.draw(textImage, in: CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: textSize))
        ctx.restoreGState()
    }
}
