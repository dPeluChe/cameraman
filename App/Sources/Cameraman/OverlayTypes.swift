//
//  OverlayTypes.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

// MARK: - Overlay Tool Enum

enum OverlayTool: CaseIterable {
    case arrow
    case rect
    case line
    case text

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
        case .line: return "Line"
        case .text: return "Text"
        }
    }

    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        }
    }

    var overlayType: Project.Overlay.OverlayType {
        switch self {
        case .arrow: return .arrow
        case .rect: return .rect
        case .line: return .line
        case .text: return .text
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .arrow: return "a"
        case .rect: return "r"
        case .line: return "l"
        case .text: return "t"
        }
    }

    var modifiers: EventModifiers {
        .command
    }
}

// MARK: - Project.Overlay.Style Extensions

extension Project.Overlay.Style {
    func with(stroke: String) -> Project.Overlay.Style {
        var copy = self
        copy.stroke = stroke
        return copy
    }

    func with(strokeWidth: Double) -> Project.Overlay.Style {
        var copy = self
        copy.strokeWidth = strokeWidth
        return copy
    }

    func with(shadow: Bool) -> Project.Overlay.Style {
        var copy = self
        copy.shadow = shadow
        return copy
    }

    func with(font: String) -> Project.Overlay.Style {
        var copy = self
        copy.font = font
        return copy
    }

    func with(size: Double) -> Project.Overlay.Style {
        var copy = self
        copy.size = size
        return copy
    }

    func with(color: String) -> Project.Overlay.Style {
        var copy = self
        copy.color = color
        return copy
    }

    func with(bg: String) -> Project.Overlay.Style {
        var copy = self
        copy.bg = bg
        return copy
    }

    func with(text: String) -> Project.Overlay.Style {
        var copy = self
        copy.text = text
        return copy
    }
}
