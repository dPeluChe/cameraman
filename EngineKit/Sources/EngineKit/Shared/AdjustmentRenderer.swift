//
//  AdjustmentRenderer.swift
//  EngineKit
//
//  Applies visual `AdjustmentConfig`s to a CIImage as a CoreImage filter chain.
//  Pure and stateless — safe to call per-frame from the compositor for any
//  layer (screen / camera / background / whole frame).
//
//  Extensible: add a new `case` (or a new `AdjustmentKind` raw value handled in
//  `applyOne`) and the whole pipeline — preview, export, MCP — picks it up.
//

import CoreImage
import CoreGraphics

enum AdjustmentRenderer {

    /// Apply every adjustment whose target matches `target` and whose absolute
    /// timeline window contains `time`, in order, to `image`.
    /// - Parameter extent: the bounds to keep the result cropped to (filters
    ///   like blur expand the extent; we clamp + re-crop to avoid growth).
    static func apply(
        _ configs: [AdjustmentConfig],
        target: Project.AdjustmentTarget,
        to image: CIImage,
        at time: TimeInterval,
        extent: CGRect
    ) -> CIImage {
        let active = configs.filter { $0.target == target && $0.isActive(at: time) }
        guard !active.isEmpty else { return image }

        var result = image
        for config in active {
            result = applyOne(config, to: result, extent: extent)
        }
        return result
    }

    /// Whether any adjustment targets the given layer at the given time. Lets the
    /// compositor skip work (e.g. avoid building a background it won't touch).
    static func hasActive(
        _ configs: [AdjustmentConfig],
        target: Project.AdjustmentTarget,
        at time: TimeInterval
    ) -> Bool {
        configs.contains { $0.target == target && $0.isActive(at: time) }
    }

    // MARK: - Single filter application

    private static func applyOne(_ config: AdjustmentConfig, to image: CIImage, extent: CGRect) -> CIImage {
        let p = config.parameters
        let kind = Project.AdjustmentKind(rawValue: config.kind)

        switch kind {
        case .sepia:
            return filtered(image, "CISepiaTone", [kCIInputIntensityKey: p["intensity"] ?? 1.0])

        case .monochrome:
            // Full desaturation = true black & white.
            return filtered(image, "CIColorControls", [kCIInputSaturationKey: 0.0])

        case .brightness:
            return filtered(image, "CIColorControls", [kCIInputBrightnessKey: p["brightness"] ?? 0.0])

        case .contrast:
            return filtered(image, "CIColorControls", [kCIInputContrastKey: p["contrast"] ?? 1.0])

        case .saturation:
            return filtered(image, "CIColorControls", [kCIInputSaturationKey: p["saturation"] ?? 1.0])

        case .colorControls:
            return filtered(image, "CIColorControls", [
                kCIInputBrightnessKey: p["brightness"] ?? 0.0,
                kCIInputContrastKey: p["contrast"] ?? 1.0,
                kCIInputSaturationKey: p["saturation"] ?? 1.0
            ])

        case .vibrance:
            return filtered(image, "CIVibrance", ["inputAmount": p["amount"] ?? 0.0])

        case .hue:
            return filtered(image, "CIHueAdjust", [kCIInputAngleKey: p["angle"] ?? 0.0])

        case .invert:
            return filtered(image, "CIColorInvert", [:])

        case .vignette:
            return filtered(image, "CIVignette", [
                kCIInputIntensityKey: p["intensity"] ?? 1.0,
                kCIInputRadiusKey: p["radius"] ?? 1.0
            ])

        case .gaussianBlur:
            // Blur reads/writes beyond the source edges; clamp first then re-crop
            // so the layer keeps its original size (no transparent halo).
            let blurred = image
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: p["radius"] ?? 8.0])
            return blurred.cropped(to: extent)

        default:
            // Unknown kind: best-effort generic CIFilter passthrough so config can
            // drive filters we haven't special-cased. Numeric params are forwarded.
            guard CIFilter(name: config.kind) != nil else { return image }
            var params: [String: Any] = [:]
            for (key, value) in p { params[key] = value }
            return filtered(image, config.kind, params)
        }
    }

    /// Apply a named CIFilter, wiring `image` as the input and forwarding params.
    /// Returns the input unchanged if the filter is unavailable or fails.
    private static func filtered(_ image: CIImage, _ name: String, _ params: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in params {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }
}
