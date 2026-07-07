//
//  CaptureGeometry+Capture.swift
//  EngineKit
//
//  NSScreen-backed factories for CaptureGeometry. Main-actor because NSScreen
//  enumeration is only guaranteed safe on the main thread.
//

import AppKit

extension CaptureGeometry {
    /// Geometry for a display capture, resolved at recording start.
    /// Returns nil for window/application captures — the captured region moves
    /// with the window, so a static rect can't map telemetry meaningfully.
    @MainActor
    public static func from(config: CaptureEngine.CaptureConfiguration) -> CaptureGeometry? {
        guard config.sourceType == .display,
              let display = config.display,
              let screen = NSScreen.screen(withDisplayID: display.id) else {
            return nil
        }

        let frame = screen.frame
        let captureRect: Rect
        if let local = config.captureRect {
            // Area selection: display-local points, top-left origin.
            captureRect = rect(fromLocalTopLeft: local, inDisplayFrame: frame)
        } else {
            captureRect = Rect(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height)
        }

        return CaptureGeometry(rect: captureRect, scale: screen.backingScaleFactor)
    }

    /// Best-effort geometry for legacy projects recorded before capture
    /// geometry was persisted: if the recorded pixel size matches an attached
    /// display exactly, assume a full-display recording on that display.
    /// Returns nil when no display matches (recording moved from another
    /// machine, area recording, or scaled quality preset).
    @MainActor
    public static func inferred(pixelWidth: Int, pixelHeight: Int) -> CaptureGeometry? {
        let matches = NSScreen.screens.filter { screen in
            let scale = screen.backingScaleFactor
            return Int(screen.frame.width * scale) == pixelWidth
                && Int(screen.frame.height * scale) == pixelHeight
        }
        // Identical displays are ambiguous — prefer the main one, the likeliest
        // recording target (its origin also matches single-display-era telemetry).
        guard let screen = matches.first(where: { $0 == NSScreen.main }) ?? matches.first else {
            return nil
        }
        let frame = screen.frame
        return CaptureGeometry(
            rect: Rect(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            scale: screen.backingScaleFactor
        )
    }
}
