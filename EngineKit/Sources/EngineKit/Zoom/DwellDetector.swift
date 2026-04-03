//
//  DwellDetector.swift
//  EngineKit
//
//  Detects cursor dwell regions (cursor stationary for >450ms) from telemetry data.
//  Inspired by OpenScreen's zoomSuggestionUtils.ts.
//  Dwell candidates are converted to ClickWindow format for seamless integration
//  with ZoomPlanGenerator.
//

import Foundation

/// Detects cursor dwell (pause) regions in telemetry data as zoom candidates.
/// A "dwell" is when the cursor stays within a small radius for a sustained period.
public struct DwellDetector {

    // MARK: - Configuration

    public struct Configuration {
        /// Minimum dwell duration to qualify as a zoom candidate (seconds)
        public var minDwellDuration: TimeInterval
        /// Maximum dwell duration — longer pauses are likely idle, not intentional focus (seconds)
        public var maxDwellDuration: TimeInterval
        /// Movement threshold — cursor must stay within this fraction of screen width to count as stationary
        /// (normalized 0–1, where 1.0 = full screen width)
        public var moveThreshold: Double
        /// Screen width for coordinate normalization (pixels)
        public var screenWidth: Double
        /// Screen height for coordinate normalization (pixels)
        public var screenHeight: Double

        public static func `default`(screenWidth: Double = 1920, screenHeight: Double = 1080) -> Configuration {
            Configuration(
                minDwellDuration: 0.3,
                maxDwellDuration: 4.0,
                moveThreshold: 0.03,
                screenWidth: screenWidth,
                screenHeight: screenHeight
            )
        }
    }

    // MARK: - Output

    public struct DwellCandidate {
        /// Midpoint timestamp of the dwell (seconds from recording start)
        public let centerTime: TimeInterval
        /// Start time of the dwell
        public let startTime: TimeInterval
        /// End time of the dwell
        public let endTime: TimeInterval
        /// Average cursor X position during dwell (normalized 0–1)
        public let focusX: Double
        /// Average cursor Y position during dwell (normalized 0–1)
        public let focusY: Double
        /// Duration of the dwell — longer = stronger signal
        public let strength: TimeInterval
    }

    // MARK: - Detection

    /// Detect dwell regions from cursor move events.
    /// - Parameters:
    ///   - events: Raw telemetry events (only .move events are used)
    ///   - config: Detection configuration
    /// - Returns: Array of dwell candidates sorted by time
    public static func detect(
        events: [TelemetryRecorder.Event],
        config: Configuration = .default()
    ) -> [DwellCandidate] {
        // Filter and sort move events
        let moves = events
            .filter { $0.type == .move }
            .sorted { $0.t < $1.t }

        guard moves.count >= 2 else { return [] }

        var candidates: [DwellCandidate] = []

        // Scan for runs of stationary cursor
        var runStart = 0

        for i in 1..<moves.count {
            let dx = Double(moves[i].x - moves[runStart].x) / config.screenWidth
            let dy = Double(moves[i].y - moves[runStart].y) / config.screenHeight
            let distance = sqrt(dx * dx + dy * dy)

            if distance > config.moveThreshold {
                // Cursor moved — evaluate the run that just ended
                if let candidate = evaluateRun(moves: moves, from: runStart, to: i - 1, config: config) {
                    candidates.append(candidate)
                }
                runStart = i
            }
        }

        // Evaluate final run
        if let candidate = evaluateRun(moves: moves, from: runStart, to: moves.count - 1, config: config) {
            candidates.append(candidate)
        }

        return candidates
    }

    // MARK: - Private

    private static func evaluateRun(
        moves: [TelemetryRecorder.Event],
        from start: Int,
        to end: Int,
        config: Configuration
    ) -> DwellCandidate? {
        guard end > start else { return nil }

        let duration = moves[end].t - moves[start].t

        guard duration >= config.minDwellDuration,
              duration <= config.maxDwellDuration else { return nil }

        // Compute centroid of all positions in this run
        var sumX: Double = 0
        var sumY: Double = 0
        let count = Double(end - start + 1)

        for i in start...end {
            sumX += Double(moves[i].x)
            sumY += Double(moves[i].y)
        }

        let avgX = sumX / count
        let avgY = sumY / count

        return DwellCandidate(
            centerTime: (moves[start].t + moves[end].t) / 2,
            startTime: moves[start].t,
            endTime: moves[end].t,
            focusX: max(0, min(1, avgX / config.screenWidth)),
            focusY: max(0, min(1, avgY / config.screenHeight)),
            strength: duration
        )
    }
}
