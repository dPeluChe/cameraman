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
        layoutType: String
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
    public var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    public var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

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

        // Get screen frame
        guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else {
            request.finish(withComposedVideoFrame: outputBuffer)
            return
        }

        // Create CIImage from screen
        let screenImage = CIImage(cvPixelBuffer: screenBuffer)
            .transformed(by: instruction.screenTransform)

        // Compose final image
        var finalImage = screenImage.cropped(to: CGRect(origin: .zero, size: renderSize))

        // Add camera if available
        if let camTrackID = instruction.cameraTrackID,
           let cameraBuffer = request.sourceFrame(byTrackID: camTrackID),
           let cameraTransform = instruction.cameraTransform {

            var cameraImage = CIImage(cvPixelBuffer: cameraBuffer)
                .transformed(by: cameraTransform)

            // Apply mask to camera
            if instruction.maskShape != .none, let cameraRect = instruction.cameraRect {
                let pixelRect = CGRect(
                    x: cameraRect.origin.x * renderSize.width,
                    y: cameraRect.origin.y * renderSize.height,
                    width: cameraRect.width * renderSize.width,
                    height: cameraRect.height * renderSize.height
                )

                cameraImage = applyMask(
                    to: cameraImage,
                    shape: instruction.maskShape,
                    rect: pixelRect,
                    cornerRadius: instruction.cornerRadius,
                    renderSize: renderSize
                )
            }

            // Composite camera on top of screen
            finalImage = cameraImage.composited(over: finalImage)
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
}
