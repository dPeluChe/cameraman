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
        // Apply translation first, then scale so offset isn't scaled
        transform = transform.concatenating(translate)
        transform = transform.scaledBy(x: CGFloat(scale), y: CGFloat(scale))

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

        let maxTime = compositionDuration.seconds

        // Filter keyframes within valid composition time range
        let validKeyframes = zoomPlan.keyframes.filter { $0.timestamp >= 0 && $0.timestamp <= maxTime }

        guard !validKeyframes.isEmpty else {
            logger.warning("No valid zoom keyframes within composition duration (\(maxTime)s), applying base transform")
            layerInstruction.setTransform(baseTransform, at: .zero)
            return
        }

        if validKeyframes.count < zoomPlan.keyframes.count {
            logger.warning("Filtered \(zoomPlan.keyframes.count - validKeyframes.count) zoom keyframes exceeding composition duration (\(maxTime)s)")
        }

        // Ensure first keyframe is applied at time zero
        if let firstKeyframe = validKeyframes.first {
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

        // Apply transform at each subsequent keyframe
        for keyframe in validKeyframes {
            let keyframeTime = CMTime(seconds: keyframe.timestamp, preferredTimescale: 600)

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
    }

    /// Calculate camera overlay transform for PiP layout
    /// - Parameters:
    ///   - cameraPosition: Camera position with normalized coordinates (0-1)
    ///   - cameraSourceSize: Size of the camera source video
    ///   - renderSize: Output render size
    /// - Returns: Transform for positioning and scaling the camera overlay
    func calculateCameraOverlayTransform(
        cameraPosition: Project.Canvas.Layout.CameraPosition,
        cameraSourceSize: CoreFoundation.CGSize,
        renderSize: CoreFoundation.CGSize
    ) -> CGAffineTransform {
        // Convert normalized coordinates to pixel coordinates
        let cameraX = cameraPosition.x * renderSize.width
        let cameraY = cameraPosition.y * renderSize.height
        let cameraW = cameraPosition.w * renderSize.width
        let cameraH = cameraPosition.h * renderSize.height

        // Calculate scale to fit camera into its target rect
        let scaleX = cameraW / cameraSourceSize.width
        let scaleY = cameraH / cameraSourceSize.height

        // Use uniform scale to maintain aspect ratio, fitting to the smaller dimension
        let scale = min(scaleX, scaleY)

        // Calculate actual scaled size
        let scaledWidth = cameraSourceSize.width * scale
        let scaledHeight = cameraSourceSize.height * scale

        // Center the camera within the target rect
        let offsetX = cameraX + (cameraW - scaledWidth) / 2
        // Flip Y axis: SwiftUI y=0 is top, AVFoundation y=0 is bottom
        let flippedY = (1.0 - cameraPosition.y - cameraPosition.h) * renderSize.height
        let offsetY = flippedY + (cameraH - scaledHeight) / 2

        logger.debug("Camera overlay: position(\(cameraX), \(cameraY)), size(\(cameraW)x\(cameraH)), scale(\(scale)), offset(\(offsetX), \(offsetY))")

        // Build transform: translate to position, then scale
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: offsetX, y: offsetY)
        transform = transform.scaledBy(x: scale, y: scale)

        return transform
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
