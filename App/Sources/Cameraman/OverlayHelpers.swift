//
//  OverlayHelpers.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    // MARK: - Helper Methods

    func selectTool(_ tool: OverlayTool) {
        selectedTool = tool
        selectedOverlayId = nil
        // Auto-create overlay at playhead with default position
        addOverlayAtPlayhead(type: tool.overlayType)
    }

    func addOverlayAtPlayhead(type: Project.Overlay.OverlayType) {
        let start = playheadTime
        // Default to 2s window — user can drag the timeline clip to extend.
        // Cap to remaining timeline; if remaining is tiny, fall back to whatever
        // fits (down to a 0.5s minimum) to avoid the "end ≤ start" validation
        // error when adding near the end.
        let remaining = editor.project.timeline.duration - start
        let defaultDuration: TimeInterval = 2.0
        let duration = max(0.5, min(defaultDuration, remaining))
        let end = start + duration

        let transform = Project.Overlay.Transform(x: 0.3, y: 0.3, scale: 1.0)
        let style = Project.Overlay.Style(
            stroke: "#FF3B30",
            strokeWidth: 3.0,
            shadow: true,
            text: type == .text ? "Text" : nil
        )
        // fadeInOut by default — user expectation is "the overlay fades in,
        // shows, fades out" within its timeline window. The previous default
        // of `nil` rendered hard cuts. Fade durations capped to ¼ of overlay
        // duration each, max 0.3s, so they never overlap or exceed.
        let fadeDuration = min(0.3, duration / 4)
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: fadeDuration,
            fadeOutDuration: fadeDuration
        )

        let overlay = Project.Overlay(
            id: UUID(),
            type: type,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
        Task {
            _ = await editor.addOverlay(projectId: editor.project.projectId, overlay: overlay)
            await MainActor.run { selectedOverlayId = overlay.id }
        }
    }

    func deleteSelectedOverlay() {
        guard let overlayId = selectedOverlayId else { return }

        Task {
            _ = await editor.deleteOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId
            )
            selectedOverlayId = nil
        }
    }

    func updateOverlay(style: Project.Overlay.Style) {
        guard let overlayId = selectedOverlayId else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                style: style
            )
        }
    }

    func updateOverlay(start: TimeInterval) {
        guard let overlayId = selectedOverlayId else { return }
        guard let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) else { return }
        guard start < overlay.end else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                start: start
            )
        }
    }

    func updateOverlay(end: TimeInterval) {
        guard let overlayId = selectedOverlayId else { return }
        guard let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) else { return }
        guard end > overlay.start else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                end: end
            )
        }
    }

    // MARK: - Animation Update Helpers

    func updateOverlayAnimation(type: Project.Overlay.Animation.AnimationType, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }

        let animation: Project.Overlay.Animation?
        if type == .none {
            animation = nil
        } else {
            let currentAnimation = overlay.animation
            animation = Project.Overlay.Animation(
                type: type,
                fadeInDuration: currentAnimation?.fadeInDuration ?? 0.3,
                fadeOutDuration: currentAnimation?.fadeOutDuration ?? 0.3,
                drawOnDuration: currentAnimation?.drawOnDuration ?? 0.5,
                easing: currentAnimation?.easing ?? .easeInOut
            )
        }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    func updateOverlayAnimation(fadeInDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    func updateOverlayAnimation(fadeOutDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    func updateOverlayAnimation(drawOnDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    func updateOverlayAnimation(easing: Project.Overlay.Animation.EasingFunction, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    // MARK: - Geometry Helpers

    func overlayRect(_ overlay: Project.Overlay, in size: CGSize) -> CGRect {
        let x = overlay.transform.x * size.width
        let y = overlay.transform.y * size.height
        let width = 100 * overlay.transform.scale
        let height = 100 * overlay.transform.scale

        return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    func normalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    func overlayAtPoint(_ point: CGPoint, in size: CGSize) -> Project.Overlay? {
        for overlay in editor.project.overlays {
            let rect = overlayRect(overlay, in: size)
            if rect.contains(point) {
                return overlay
            }
        }
        return nil
    }

    func defaultStyle(for tool: OverlayTool) -> Project.Overlay.Style {
        switch tool {
        case .arrow, .line:
            return Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            )
        case .rect:
            return Project.Overlay.Style(
                stroke: "#007AFF",
                strokeWidth: 2.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: "#007AFF",
                text: nil
            )
        case .text:
            return Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#000000",
                bg: nil,
                text: "Text"
            )
        }
    }

    func color(from hex: String) -> Color {
        guard let rgba = rgba(from: hex) else {
            return .primary
        }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    func rgba(from hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 6: // RGB
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8: // ARGB
            r = Double((rgb & 0x00FF0000) >> 16) / 255.0
            g = Double((rgb & 0x0000FF00) >> 8) / 255.0
            b = Double(rgb & 0x000000FF) / 255.0
            a = Double((rgb & 0xFF000000) >> 24) / 255.0
        default:
            return nil
        }

        return (r, g, b, a)
    }

    func hexColor(from color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent * 255),
                      Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255))
    }
}
