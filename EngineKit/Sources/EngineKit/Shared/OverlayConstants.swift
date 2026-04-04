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
        }
    }

    /// Absolute base size in pixels for a given canvas size
    public static func size(for type: Project.Overlay.OverlayType, canvasSize: CGSize) -> CGSize {
        let rel = relativeSize(for: type)
        return CGSize(width: rel.width * canvasSize.width, height: rel.height * canvasSize.height)
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
        }
    }

    public static func label(for type: Project.Overlay.OverlayType) -> String {
        switch type {
        case .arrow: return "Arrow"
        case .rect: return "Rect"
        case .line: return "Line"
        case .text: return "Text"
        }
    }
}
