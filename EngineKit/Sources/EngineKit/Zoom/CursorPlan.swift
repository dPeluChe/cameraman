//
//  CursorPlan.swift
//  EngineKit
//
//  Synthetic cursor rendering data: a resampled cursor path + click marks in
//  the same normalized (0-1, bottom-left origin) space `ZoomPlan` uses,
//  derived from raw telemetry rebased into capture-local space via
//  `CaptureGeometry`. Consumed by `MaskedVideoCompositor` to draw a cursor
//  dot/arrow and click ripples on top of the composited frame.
//

import Foundation

/// One resampled cursor position at a point in time.
public struct CursorSample: Codable, Equatable, Sendable {
    public let time: TimeInterval
    /// Normalized position (0-1), bottom-left origin — matches `CaptureGeometry.normalized`.
    public let x: Double
    public let y: Double

    public init(time: TimeInterval, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

/// A mouse-down event, used to render click ripples.
public struct CursorClickMark: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let x: Double
    public let y: Double

    public init(time: TimeInterval, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

/// Resampled cursor path + click marks for synthetic cursor rendering.
public struct CursorPlan: Codable, Equatable, Sendable {
    public let samples: [CursorSample]
    public let clicks: [CursorClickMark]

    public init(samples: [CursorSample], clicks: [CursorClickMark]) {
        self.samples = samples
        self.clicks = clicks
    }

    public static let empty = CursorPlan(samples: [], clicks: [])

    /// Interpolated cursor position at `time`, or nil if `time` falls outside
    /// the recorded range (nothing to draw before the first / after the last sample).
    public func position(at time: TimeInterval) -> (x: Double, y: Double)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time { return (first.x, first.y) }
        if time >= last.time { return (last.x, last.y) }

        // Samples are sorted by time; binary search for the surrounding pair.
        var lo = 0
        var hi = samples.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = samples[lo]
        let b = samples[hi]
        let span = b.time - a.time
        guard span > 0 else { return (a.x, a.y) }
        let t = (time - a.time) / span
        return (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    /// Click marks still within `rippleDuration` of `time`, with normalized
    /// age in 0...1 (0 = just clicked, 1 = ripple finished) for the caller to
    /// scale/fade the ripple effect.
    public func activeRipples(at time: TimeInterval, rippleDuration: TimeInterval = 0.5) -> [(mark: CursorClickMark, age: Double)] {
        clicks.compactMap { mark in
            let elapsed = time - mark.time
            guard elapsed >= 0, elapsed <= rippleDuration else { return nil }
            return (mark, elapsed / rippleDuration)
        }
    }
}

/// Builds a `CursorPlan` from raw telemetry events already rebased into
/// capture-local point space (see `CaptureGeometry.rebaseToCaptureSpace`).
public enum CursorPlanGenerator {
    /// - Parameters:
    ///   - events: Raw telemetry events in capture-local points (origin bottom-left).
    ///   - screenWidth/screenHeight: Capture-space dimensions (`CaptureGeometry.rect.w/h`).
    public static func generate(
        from events: [TelemetryRecorder.Event],
        screenWidth: Double,
        screenHeight: Double
    ) -> CursorPlan {
        guard screenWidth > 0, screenHeight > 0, !events.isEmpty else { return .empty }

        let sorted = events.sorted { $0.t < $1.t }
        let samples = sorted.map { event in
            CursorSample(
                time: event.t,
                x: min(1, max(0, Double(event.x) / screenWidth)),
                y: min(1, max(0, Double(event.y) / screenHeight))
            )
        }
        let clicks = sorted
            .filter { $0.type == .down }
            .map { event in
                CursorClickMark(
                    time: event.t,
                    x: min(1, max(0, Double(event.x) / screenWidth)),
                    y: min(1, max(0, Double(event.y) / screenHeight))
                )
            }

        return CursorPlan(samples: samples, clicks: clicks)
    }
}
