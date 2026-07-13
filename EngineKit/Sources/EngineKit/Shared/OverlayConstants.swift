//
//  OverlayConstants.swift
//  EngineKit
//
//  Shared overlay constants and helpers used across compositor, export, and preview.
//

import Foundation

// MARK: - Base sizes (relative to canvas)

public enum OverlayBaseSize {
    /// Base size as fraction of canvas size for each overlay type
    public static func relativeSize(for type: Project.Overlay.OverlayType) -> CGSize {
        switch type {
        case .arrow: return CGSize(width: 0.15, height: 0.08)
        case .rect: return CGSize(width: 0.25, height: 0.18)
        case .line: return CGSize(width: 0.30, height: 0.005)
        case .text: return CGSize(width: 0.35, height: 0.06)
        case .image: return CGSize(width: 0.25, height: 0.25)
        }
    }

    /// Absolute base size in pixels for a given canvas size
    public static func size(for type: Project.Overlay.OverlayType, canvasSize: CGSize) -> CGSize {
        let rel = relativeSize(for: type)
        return CGSize(width: rel.width * canvasSize.width, height: rel.height * canvasSize.height)
    }
}

public enum OverlayCanvasGeometry {
    public struct SnapResult: Equatable, Sendable {
        public let center: CGPoint
        public let verticalGuide: CGFloat?
        public let horizontalGuide: CGFloat?
    }

    public static func normalizedPoint(fromViewPoint point: CGPoint, in canvasSize: CGSize) -> CGPoint? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        return CGPoint(
            x: min(1, max(0, point.x / canvasSize.width)),
            y: min(1, max(0, point.y / canvasSize.height))
        )
    }

    public static func viewPoint(x: Double, y: Double, in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: x * canvasSize.width, y: y * canvasSize.height)
    }

    public static func renderPoint(x: Double, y: Double, in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: x * canvasSize.width, y: (1 - y) * canvasSize.height)
    }

    public static func viewRect(
        x: Double,
        y: Double,
        relativeSize: CGSize,
        scale: Double,
        in canvasSize: CGSize
    ) -> CGRect {
        let center = viewPoint(x: x, y: y, in: canvasSize)
        let width = relativeSize.width * canvasSize.width * scale
        let height = relativeSize.height * canvasSize.height * scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    public static func normalizedTranslation(_ translation: CGSize, in canvasSize: CGSize) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        return CGPoint(
            x: translation.width / canvasSize.width,
            y: translation.height / canvasSize.height
        )
    }

    public static func safeAreaRect(in canvasSize: CGSize, inset: CGFloat = 0.05) -> CGRect {
        CGRect(
            x: canvasSize.width * inset,
            y: canvasSize.height * inset,
            width: canvasSize.width * (1 - inset * 2),
            height: canvasSize.height * (1 - inset * 2)
        )
    }

    public static func snappedCenter(
        proposed: CGPoint,
        relativeSize: CGSize,
        scale: Double,
        rotationDegrees: Double,
        in canvasSize: CGSize,
        thresholdPixels: CGFloat = 8,
        safeInset: CGFloat = 0.05
    ) -> SnapResult {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return SnapResult(center: proposed, verticalGuide: nil, horizontalGuide: nil)
        }

        let radians = CGFloat(rotationDegrees * .pi / 180)
        let width = relativeSize.width * CGFloat(scale)
        let height = relativeSize.height * CGFloat(scale)
        let halfWidth = min(0.5, (abs(width * cos(radians)) + abs(height * sin(radians))) / 2)
        let halfHeight = min(0.5, (abs(width * sin(radians)) + abs(height * cos(radians))) / 2)

        let constrained = CGPoint(
            x: constrain(proposed.x, halfExtent: halfWidth),
            y: constrain(proposed.y, halfExtent: halfHeight)
        )
        let xCandidates = axisCandidates(halfExtent: halfWidth, safeInset: safeInset)
        let yCandidates = axisCandidates(halfExtent: halfHeight, safeInset: safeInset)
        let xSnap = nearestSnap(
            to: constrained.x,
            candidates: xCandidates,
            threshold: thresholdPixels / canvasSize.width
        )
        let ySnap = nearestSnap(
            to: constrained.y,
            candidates: yCandidates,
            threshold: thresholdPixels / canvasSize.height
        )

        return SnapResult(
            center: CGPoint(x: xSnap?.value ?? constrained.x, y: ySnap?.value ?? constrained.y),
            verticalGuide: xSnap?.guide,
            horizontalGuide: ySnap?.guide
        )
    }

    private static func constrain(_ value: CGFloat, halfExtent: CGFloat) -> CGFloat {
        guard halfExtent < 0.5 else { return 0.5 }
        return min(1 - halfExtent, max(halfExtent, value))
    }

    private static func axisCandidates(
        halfExtent: CGFloat,
        safeInset: CGFloat
    ) -> [(value: CGFloat, guide: CGFloat)] {
        let leading = safeInset + halfExtent
        let trailing = 1 - safeInset - halfExtent
        var candidates: [(CGFloat, CGFloat)] = [(0.5, 0.5)]
        if leading <= trailing {
            candidates.append((leading, safeInset))
            candidates.append((trailing, 1 - safeInset))
        }
        return candidates
    }

    private static func nearestSnap(
        to value: CGFloat,
        candidates: [(value: CGFloat, guide: CGFloat)],
        threshold: CGFloat
    ) -> (value: CGFloat, guide: CGFloat)? {
        candidates
            .map { (value: $0.value, guide: $0.guide, distance: abs(value - $0.value)) }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }
            .map { (value: $0.value, guide: $0.guide) }
    }
}

// MARK: - Icon and label helpers

public enum OverlayDisplayInfo {
    public static func icon(for type: Project.Overlay.OverlayType) -> String {
        switch type {
        case .arrow: return "arrowshape.right.fill"
        case .rect: return "rectangle.fill"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .image: return "photo"
        }
    }

    public static func label(for type: Project.Overlay.OverlayType) -> String {
        switch type {
        case .arrow: return "Arrow"
        case .rect: return "Rect"
        case .line: return "Line"
        case .text: return "Text"
        case .image: return "Image"
        }
    }
}
