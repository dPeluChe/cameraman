//
//  CompositorRenderers.swift
//  EngineKit
//
//  Rendering helpers for MaskedVideoCompositor: masks, backgrounds,
//  static content, camera borders, video effects, and color parsing.
//

import CoreImage
import CoreGraphics
import AVFoundation

extension MaskedVideoCompositor {

    // MARK: - Shared Shape Path

    /// Build a CGPath for the given PiP mask shape. Returns nil for `.none`.
    func shapePath(for shape: PiPMaskShape, rect: CGRect, cornerRadius: CGFloat) -> CGPath? {
        switch shape {
        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                width: diameter, height: diameter
            )
            return CGPath(ellipseIn: circleRect, transform: nil)
        case .roundedRect:
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .none:
            return nil
        }
    }

    /// Apply a CIBlendWithMask using a path-based mask over the given image.
    func applyPathMask(to image: CIImage, path: CGPath, renderSize: CGSize) -> CIImage {
        guard let ctx = createBGRAContext(size: renderSize) else { return image }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: renderSize))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()

        guard let maskCGImage = ctx.makeImage() else { return image }
        let maskCIImage = CIImage(cgImage: maskCGImage)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return image }
        let clearBG = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(clearBG, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    // MARK: - Mask Application

    func applyMask(
        to image: CIImage,
        shape: PiPMaskShape,
        rect: CGRect,
        cornerRadius: CGFloat,
        renderSize: CGSize
    ) -> CIImage {
        guard let path = shapePath(for: shape, rect: rect, cornerRadius: cornerRadius) else {
            return image
        }
        return applyPathMask(to: image, path: path, renderSize: renderSize)
    }

    // MARK: - Static Content

    func renderStaticContent(_ content: MaskedVideoCompositionInstruction.StaticClipContent, renderSize: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: renderSize)

        switch content {
        case .image(let path):
            cacheLock.lock()
            if let cached = cachedStaticImages[path] {
                cacheLock.unlock()
                return fitImageToCanvas(cached, renderSize: renderSize)
            }
            cacheLock.unlock()

            guard let cgImage = loadCGImage(from: path) else {
                return CIImage(color: .black).cropped(to: canvasRect)
            }
            let ciImage = CIImage(cgImage: cgImage)

            cacheLock.lock()
            cachedStaticImages[path] = ciImage
            cacheLock.unlock()

            return fitImageToCanvas(ciImage, renderSize: renderSize)

        case .color(let hexColor):
            return CIImage(color: ciColor(from: hexColor)).cropped(to: canvasRect)
        }
    }

    private func fitImageToCanvas(_ image: CIImage, renderSize: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: renderSize)
        let imageExtent = image.extent

        guard imageExtent.width > 0 && imageExtent.height > 0 else {
            return CIImage(color: .black).cropped(to: canvasRect)
        }

        let scale = min(renderSize.width / imageExtent.width, renderSize.height / imageExtent.height)
        let offsetX = (renderSize.width - imageExtent.width * scale) / 2
        let offsetY = (renderSize.height - imageExtent.height * scale) / 2

        let background = CIImage(color: .black).cropped(to: canvasRect)
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: canvasRect)

        return scaled.composited(over: background)
    }

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

    func renderBackground(instruction: MaskedVideoCompositionInstruction, renderSize: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: renderSize)
        switch instruction.backgroundType {
        case "gradient":
            return renderGradientBackground(value: instruction.backgroundValue, size: renderSize)
        case "solid":
            return CIImage(color: ciColor(from: instruction.backgroundValue)).cropped(to: rect)
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

    // MARK: - Video Effects

    func applyCornerRadius(to image: CIImage, radius: CGFloat, renderSize: CGSize, padding: CGFloat) -> CIImage {
        let scale = 1.0 - padding
        let insetW = renderSize.width * scale
        let insetH = renderSize.height * scale
        let offsetX = (renderSize.width - insetW) / 2
        let offsetY = (renderSize.height - insetH) / 2
        let videoRect = CGRect(x: offsetX, y: offsetY, width: insetW, height: insetH)

        let path = CGPath(roundedRect: videoRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        return applyPathMask(to: image, path: path, renderSize: renderSize)
    }

    // MARK: - Camera Border

    func renderCameraBorder(
        shape: PiPMaskShape, rect: CGRect, cornerRadius: CGFloat,
        borderWidth: CGFloat, borderColor: String, renderSize: CGSize
    ) -> CIImage {
        let clearResult = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: renderSize))
        guard let borderPath = shapePath(for: shape, rect: rect, cornerRadius: cornerRadius) else {
            return clearResult
        }

        guard let ctx = createBGRAContext(size: renderSize) else { return clearResult }

        ctx.clear(CGRect(origin: .zero, size: renderSize))
        ctx.setStrokeColor(cgColor(from: borderColor))
        ctx.setLineWidth(borderWidth)
        ctx.addPath(borderPath)
        ctx.strokePath()

        guard let cgImage = ctx.makeImage() else { return clearResult }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Color Parsing

    func ciColor(from hex: String) -> CIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if clean.count == 8, let rgba = UInt64(clean, radix: 16) {
            return CIColor(
                red: CGFloat((rgba >> 24) & 0xFF) / 255.0,
                green: CGFloat((rgba >> 16) & 0xFF) / 255.0,
                blue: CGFloat((rgba >> 8) & 0xFF) / 255.0,
                alpha: CGFloat(rgba & 0xFF) / 255.0
            )
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return .black }
        return CIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0
        )
    }

    func cgColor(from hex: String) -> CGColor {
        let ci = ciColor(from: hex)
        return CGColor(red: ci.red, green: ci.green, blue: ci.blue, alpha: ci.alpha)
    }

    // MARK: - Shared Context Helper

    private static let sharedColorSpace = CGColorSpaceCreateDeviceRGB()

    func createBGRAContext(size: CGSize) -> CGContext? {
        CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
            space: Self.sharedColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
