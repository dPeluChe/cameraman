//
//  ExportTransformUtils.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import CoreGraphics
import AVFoundation

extension ExportEngine {
    /// Calculate downscale transform from source to output size
    func calculateDownscaleTransform(
        from sourceSize: CoreFoundation.CGSize,
        to outputSize: CoreFoundation.CGSize,
        contentMode: String
    ) -> CGAffineTransform {
        let sourceAspect = sourceSize.width / sourceSize.height
        let outputAspect = outputSize.width / outputSize.height

        var scale: CoreFoundation.CGFloat
        var translate = CGAffineTransform.identity

        if contentMode == "fit" {
            // Letterbox/pillarbox - fit entire source within output
            if sourceAspect > outputAspect {
                // Source is wider - scale to fit width
                scale = outputSize.width / sourceSize.width
                let scaledHeight = sourceSize.height * scale
                let yOffset = (outputSize.height - scaledHeight) / 2
                translate = CGAffineTransform(translationX: 0, y: yOffset)
            } else {
                // Source is taller - scale to fit height
                scale = outputSize.height / sourceSize.height
                let scaledWidth = sourceSize.width * scale
                let xOffset = (outputSize.width - scaledWidth) / 2
                translate = CGAffineTransform(translationX: xOffset, y: 0)
            }
        } else {
            // Fill - crop to fill output
            if sourceAspect > outputAspect {
                // Source is wider - scale to fit height (crop sides)
                scale = outputSize.height / sourceSize.height
                let scaledWidth = sourceSize.width * scale
                let xOffset = (outputSize.width - scaledWidth) / 2
                translate = CGAffineTransform(translationX: xOffset, y: 0)
            } else {
                // Source is taller - scale to fit width (crop top/bottom)
                scale = outputSize.width / sourceSize.width
                let scaledHeight = sourceSize.height * scale
                let yOffset = (outputSize.height - scaledHeight) / 2
                translate = CGAffineTransform(translationX: 0, y: yOffset)
            }
        }

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: CGFloat(scale), y: CGFloat(scale))
        transform = transform.concatenating(translate)

        return transform
    }

    /// Apply zoom transforms to layer instruction based on zoom plan keyframes
    /// - Parameters:
    ///   - layerInstruction: Layer instruction to apply transforms to
    ///   - zoomPlan: Zoom plan with keyframes
    ///   - baseTransform: Base transform (downscale, layout, etc.)
    ///   - sourceSize: Source video size
    ///   - renderSize: Output render size
    ///   - compositionDuration: Total composition duration
    /// - Throws: ExportError if transform application fails
    func applyZoomTransforms(
        to layerInstruction: AVMutableVideoCompositionLayerInstruction,
        zoomPlan: ZoomPlanGenerator.ZoomPlan,
        baseTransform: CGAffineTransform,
        sourceSize: CoreFoundation.CGSize,
        renderSize: CoreFoundation.CGSize,
        compositionDuration: CMTime
    ) async throws {
        guard !zoomPlan.keyframes.isEmpty else {
            // No keyframes, just apply base transform
            layerInstruction.setTransform(baseTransform, at: .zero)
            return
        }

        // Apply transform at each keyframe
        for keyframe in zoomPlan.keyframes {
            let keyframeTime = CMTime(seconds: keyframe.timestamp, preferredTimescale: 600)

            // Calculate zoom transform
            let zoomTransform = calculateZoomTransform(
                zoomLevel: keyframe.zoomLevel,
                focusX: keyframe.focusX,
                focusY: keyframe.focusY,
                baseTransform: baseTransform,
                sourceSize: sourceSize,
                renderSize: renderSize
            )

            layerInstruction.setTransform(zoomTransform, at: keyframeTime)
        }

        // Ensure first keyframe is applied at time zero
        if let firstKeyframe = zoomPlan.keyframes.first {
            let firstTransform = calculateZoomTransform(
                zoomLevel: firstKeyframe.zoomLevel,
                focusX: firstKeyframe.focusX,
                focusY: firstKeyframe.focusY,
                baseTransform: baseTransform,
                sourceSize: sourceSize,
                renderSize: renderSize
            )
            layerInstruction.setTransform(firstTransform, at: .zero)
        }
    }

    /// Calculate zoom transform for a specific zoom level and focus point
    /// - Parameters:
    ///   - zoomLevel: Zoom level (1.0 = no zoom, 2.0 = 2x zoom)
    ///   - focusX: Focus point X (normalized 0.0-1.0)
    ///   - focusY: Focus point Y (normalized 0.0-1.0)
    ///   - baseTransform: Base transform to apply zoom on top of
    ///   - sourceSize: Source video size
    ///   - renderSize: Output render size
    /// - Returns: Combined transform with zoom applied
    private func calculateZoomTransform(
        zoomLevel: Double,
        focusX: Double,
        focusY: Double,
        baseTransform: CGAffineTransform,
        sourceSize: CoreFoundation.CGSize,
        renderSize: CoreFoundation.CGSize
    ) -> CGAffineTransform {
        // Only apply zoom if zoom level is significant (> 1.01)
        guard zoomLevel > 1.01 else {
            return baseTransform
        }

        // Calculate focus point in render coordinates
        let focusPointRender = CGPoint(
            x: CGFloat(focusX) * renderSize.width,
            y: CGFloat(focusY) * renderSize.height
        )

        // Create zoom transform
        // 1. Translate to focus point
        let translateToFocus = CGAffineTransform(translationX: focusPointRender.x, y: focusPointRender.y)

        // 2. Scale by zoom level
        let scale = CGAffineTransform(scaleX: CGFloat(zoomLevel), y: CGFloat(zoomLevel))

        // 3. Translate back from focus point
        let translateFromFocus = CGAffineTransform(translationX: -focusPointRender.x, y: -focusPointRender.y)

        // Combine transforms: base -> translate to focus -> scale -> translate back
        var zoomTransform = baseTransform
        zoomTransform = zoomTransform.concatenating(translateToFocus)
        zoomTransform = zoomTransform.concatenating(scale)
        zoomTransform = zoomTransform.concatenating(translateFromFocus)

        return zoomTransform
    }
}
