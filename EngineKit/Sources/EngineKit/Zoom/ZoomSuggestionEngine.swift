//
//  ZoomSuggestionEngine.swift
//  EngineKit
//
//  High-level API that combines click-based and dwell-based zoom detection
//  into a unified list of zoom suggestions. Feeds into ZoomPlanGenerator.
//

import Foundation

/// A zoom suggestion from either cursor clicks or cursor dwell (pause).
public struct ZoomSuggestion: Identifiable, Sendable {
    public let id: UUID
    /// Timeline time for the zoom center (seconds)
    public let timelineTime: TimeInterval
    /// Normalized focus X (0-1)
    public let focusX: Double
    /// Normalized focus Y (0-1)
    public let focusY: Double
    /// Suggested zoom level
    public let zoomLevel: Double
    /// Where this suggestion came from
    public let source: Source
    /// Confidence / importance score (higher = stronger signal)
    public let score: Double

    public enum Source: String, Sendable {
        case click
        case dwell
    }

    public init(
        id: UUID = UUID(),
        timelineTime: TimeInterval,
        focusX: Double,
        focusY: Double,
        zoomLevel: Double,
        source: Source,
        score: Double
    ) {
        self.id = id
        self.timelineTime = timelineTime
        self.focusX = focusX
        self.focusY = focusY
        self.zoomLevel = zoomLevel
        self.source = source
        self.score = score
    }

    /// Convert a suggestion to ClickWindow format for ZoomPlanGenerator compatibility.
    func toClickWindow(screenWidth: Double, screenHeight: Double) -> TelemetryParser.ClickWindow {
        let cx = Int(focusX * screenWidth)
        let cy = Int(focusY * screenHeight)
        let halfSize = 30

        return TelemetryParser.ClickWindow(
            id: id,
            startTime: timelineTime,
            endTime: timelineTime + 0.5,
            clicks: [],
            centerPoint: CGPoint(x: CGFloat(cx), y: CGFloat(cy)),
            boundingBox: TelemetryParser.BoundingBox(
                minX: cx - halfSize, maxX: cx + halfSize,
                minY: cy - halfSize, maxY: cy + halfSize
            ),
            importanceScore: score
        )
    }
}

/// Stateless namespace for zoom suggestion generation and application.
public enum ZoomSuggestionEngine {

    private static let deduplicationWindow: TimeInterval = 0.8

    /// Generate zoom suggestions from raw telemetry events.
    /// Combines click-based detection (via TelemetryParser) and dwell-based detection.
    public static func generateSuggestions(
        events: [TelemetryRecorder.Event],
        parseResult: TelemetryParser.ParseResult,
        screenWidth: Double = 1920,
        screenHeight: Double = 1080,
        timelineDuration: TimeInterval
    ) -> [ZoomSuggestion] {
        var suggestions: [ZoomSuggestion] = []

        // Click-based suggestions from existing click windows
        for window in parseResult.windows {
            let focusX = window.centerPoint.x / screenWidth
            let focusY = window.centerPoint.y / screenHeight

            let area = Double(window.boundingBox.width * window.boundingBox.height)
            let normalized = max(0.01, min(1.0, area / (screenWidth * screenHeight)))
            let zoomLevel = 2.5 - (normalized * 1.5)

            suggestions.append(ZoomSuggestion(
                timelineTime: window.startTime,
                focusX: max(0, min(1, focusX)),
                focusY: max(0, min(1, focusY)),
                zoomLevel: max(1.5, min(3.5, zoomLevel)),
                source: .click,
                score: window.importanceScore
            ))
        }

        // Dwell-based suggestions
        let dwellConfig = DwellDetector.Configuration.default(
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
        let dwells = DwellDetector.detect(events: events, config: dwellConfig)

        for dwell in dwells {
            suggestions.append(ZoomSuggestion(
                timelineTime: dwell.centerTime,
                focusX: dwell.focusX,
                focusY: dwell.focusY,
                zoomLevel: 2.0,
                source: .dwell,
                score: dwell.strength * 10
            ))
        }

        // Deduplicate nearby suggestions (keep highest score)
        suggestions.sort { $0.timelineTime < $1.timelineTime }
        var filtered: [ZoomSuggestion] = []
        for suggestion in suggestions {
            if let last = filtered.last, suggestion.timelineTime - last.timelineTime < deduplicationWindow {
                if suggestion.score > last.score {
                    filtered[filtered.count - 1] = suggestion
                }
                continue
            }
            filtered.append(suggestion)
        }

        return filtered
    }

    /// Apply selected suggestions as a zoom plan.
    public static func applyAsPlan(
        suggestions: [ZoomSuggestion],
        config: ZoomPlanGenerator.Configuration = .default(),
        screenWidth: Double = 1920,
        screenHeight: Double = 1080,
        timelineDuration: TimeInterval
    ) async throws -> ZoomPlanGenerator.ZoomPlan {
        let clickWindows = suggestions.map { $0.toClickWindow(screenWidth: screenWidth, screenHeight: screenHeight) }
        let generator = ZoomPlanGenerator()
        return try await generator.generateZoomPlan(
            from: clickWindows,
            config: config,
            timelineDuration: timelineDuration
        )
    }
}
