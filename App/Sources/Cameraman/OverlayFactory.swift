//
//  OverlayFactory.swift
//  App
//
//  Single source of truth for overlay creation defaults. The overlay toolbar,
//  the preview drag-and-drop path, and the preview context menu all create
//  overlays — before this factory each duplicated the default window/style/
//  fade logic and they could drift apart.
//

import AppKit
import EngineKit
import UniformTypeIdentifiers

enum OverlayFactory {
    /// Default overlay window — user can drag the timeline clip to extend.
    private static let defaultDuration: TimeInterval = 2.0

    /// Clamp the overlay window to the remaining timeline; if remaining is
    /// tiny, fall back to whatever fits (down to a 0.5s minimum) to avoid the
    /// "end ≤ start" validation error when adding near the end.
    private static func window(at start: TimeInterval, timelineDuration: TimeInterval) -> (end: TimeInterval, fade: TimeInterval) {
        let remaining = timelineDuration - start
        let duration = max(0.5, min(defaultDuration, remaining))
        // fadeInOut by default — user expectation is "the overlay fades in,
        // shows, fades out" within its timeline window. Fade durations capped
        // to ¼ of overlay duration each, max 0.3s, so they never overlap.
        return (start + duration, min(0.3, duration / 4))
    }

    /// Shape/text overlay with the standard red-stroke defaults.
    static func shapeOverlay(
        type: Project.Overlay.OverlayType,
        at start: TimeInterval,
        timelineDuration: TimeInterval
    ) -> Project.Overlay {
        let (end, fade) = window(at: start, timelineDuration: timelineDuration)
        return Project.Overlay(
            id: UUID(),
            type: type,
            start: start,
            end: end,
            transform: Project.Overlay.Transform(x: 0.3, y: 0.3, scale: 1.0),
            style: Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                text: type == .text ? "Text" : nil
            ),
            animation: Project.Overlay.Animation(
                type: .fadeInOut,
                fadeInDuration: fade,
                fadeOutDuration: fade
            )
        )
    }

    /// Image overlay. `position` is in renderer convention — (0.5, 0.5) is
    /// visually dead-center of the preview canvas.
    static func imageOverlay(
        imagePath: String,
        at start: TimeInterval,
        timelineDuration: TimeInterval,
        position: (x: Double, y: Double) = (0.5, 0.5)
    ) -> Project.Overlay {
        let (end, fade) = window(at: start, timelineDuration: timelineDuration)
        return Project.Overlay(
            id: UUID(),
            type: .image,
            start: start,
            end: end,
            transform: Project.Overlay.Transform(x: position.x, y: position.y, scale: 1.0),
            style: Project.Overlay.Style(
                stroke: "#FFFFFF",
                strokeWidth: 0,
                shadow: false,
                imagePath: imagePath,
                imageOpacity: 1.0
            ),
            animation: Project.Overlay.Animation(
                type: .fadeInOut,
                fadeInDuration: fade,
                fadeOutDuration: fade
            )
        )
    }

    /// Standard open panel for picking an overlay image. Calls `onPick` on the
    /// main actor with the selected file path.
    @MainActor
    static func presentImagePicker(onPick: @escaping @MainActor (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an image, SVG, or GIF to add as overlay"
        // .image as content type covers PNG, JPEG, HEIC, GIF and many more.
        // SVG (public.svg-image) isn't a child of .image on macOS so add it
        // explicitly.
        panel.allowedContentTypes = [.image, .svg, .gif]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                onPick(url.path)
            }
        }
    }
}
