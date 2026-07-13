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
