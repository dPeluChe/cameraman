//
//  CaptureGeometry.swift
//  EngineKit
//
//  Geometry of a screen recording: which region of which display the video
//  shows, expressed in the SAME coordinate space as cursor telemetry
//  (global Cocoa display points, origin at the bottom-left of the main display).
//
//  Cursor telemetry is captured via NSEvent in global screen POINTS, while the
//  recorded video is measured in physical PIXELS (points × backingScaleFactor)
//  and — for area recordings — cropped to a sub-region. Persisting this
//  geometry with the recording is what allows telemetry to be mapped onto the
//  video reliably (zoom focus, click markers, cursor overlays).
//

import Foundation

public struct CaptureGeometry: Codable, Equatable, Sendable {
    /// Axis-aligned rectangle in global Cocoa display points (bottom-left origin).
    public struct Rect: Codable, Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    /// Region of the screen shown in the video, in global Cocoa points —
    /// the exact space cursor telemetry events (x, y) live in.
    public let rect: Rect
    /// backingScaleFactor of the captured display (1.0 standard, 2.0 Retina).
    public let scale: Double

    public init(rect: Rect, scale: Double) {
        self.rect = rect
        self.scale = scale
    }

    // MARK: - Telemetry mapping

    /// Whether a telemetry position (global Cocoa points) falls inside the captured region.
    public func contains(x: Double, y: Double) -> Bool {
        x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h
    }

    /// Map a telemetry position (global Cocoa points) to normalized video
    /// space: 0–1 with bottom-left origin, matching the convention the zoom
    /// render pipeline already uses. Out-of-region positions are clamped.
    public func normalized(x: Double, y: Double) -> (x: Double, y: Double) {
        guard rect.w > 0, rect.h > 0 else { return (0, 0) }
        let nx = (x - rect.x) / rect.w
        let ny = (y - rect.y) / rect.h
        return (min(1, max(0, nx)), min(1, max(0, ny)))
    }

    /// Rebase telemetry events into capture-local points (origin at the capture
    /// rect's bottom-left corner), dropping events outside the captured region —
    /// clicks outside a recorded area must not produce zoom targets. The
    /// resulting events pair with `rect.w` / `rect.h` as the screen dimensions
    /// expected by `TelemetryParser` / `DwellDetector` / `ZoomPlanGenerator`.
    public func rebaseToCaptureSpace(_ events: [TelemetryRecorder.Event]) -> [TelemetryRecorder.Event] {
        events.compactMap { event in
            let ex = Double(event.x)
            let ey = Double(event.y)
            guard contains(x: ex, y: ey) else { return nil }
            return TelemetryRecorder.Event(
                t: event.t,
                type: event.type,
                x: Int((ex - rect.x).rounded()),
                y: Int((ey - rect.y).rounded()),
                button: event.button,
                dx: event.dx,
                dy: event.dy,
                displayID: event.displayID
            )
        }
    }

    // MARK: - Rect conversion

    /// Convert a display-local rect with TOP-left origin (the space
    /// `ScreenAreaSelector` / `SCStreamConfiguration.sourceRect` use) into
    /// global Cocoa points (bottom-left origin), given the display's frame
    /// in global Cocoa points.
    public static func rect(fromLocalTopLeft local: CGRect, inDisplayFrame frame: CGRect) -> Rect {
        Rect(
            x: frame.minX + local.minX,
            y: frame.maxY - local.maxY,
            w: local.width,
            h: local.height
        )
    }
}
