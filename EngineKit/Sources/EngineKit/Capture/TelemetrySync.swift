//
//  TelemetrySync.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation

/// TelemetrySync handles timeline synchronization and validation for telemetry data
public actor TelemetrySync {

    public init() {}

    // MARK: - Public Methods

    /// Synchronize telemetry events with timeline
    /// - Parameters:
    ///   - telemetryFile: Path to cursor.jsonl file
    ///   - timeline: Timeline model from project
    ///   - config: Synchronization configuration
    /// - Returns: SyncResult with synchronized events and validation
    public func synchronize(
        telemetryFile: URL,
        timeline: Project.Timeline,
        config: Configuration = .default
    ) async throws -> SyncResult {
        // Load telemetry events
        let events = try loadTelemetryEvents(from: telemetryFile)

        // Synchronize with timeline segments
        let syncedEvents = try syncEventsWithTimeline(events, timeline: timeline)

        // Validate synchronization
        let validation = validateSynchronization(
            syncedEvents,
            timeline: timeline,
            config: config
        )

        // Calculate statistics
        let stats = calculateStatistics(for: syncedEvents, timeline: timeline)

        return SyncResult(
            events: syncedEvents,
            validation: validation,
            stats: stats
        )
    }

    /// Create debug overlay data for visualization
    /// - Parameters:
    ///   - syncedEvents: Synchronized telemetry events
    ///   - timeRange: Time range to include in overlay
    /// - Returns: DebugOverlay with cursor positions and click events
    public func createDebugOverlay(
        syncedEvents: [SyncedEvent],
        timeRange: ClosedRange<TimeInterval>
    ) -> DebugOverlay {
        // Filter events within time range
        let filteredEvents = syncedEvents.filter { timeRange.contains($0.timelineTimestamp) }

        // Extract cursor positions from move events
        let cursorPositions = filteredEvents
            .filter { $0.event.type == .move }
            .map { event in
                DebugOverlay.CursorPosition(
                    x: event.event.x,
                    y: event.event.y,
                    timestamp: event.timelineTimestamp,
                    displayID: event.event.displayID
                )
            }

        // Extract click events
        let clickEvents = filteredEvents
            .filter { $0.event.type == .down || $0.event.type == .up }
            .compactMap { event -> DebugOverlay.ClickEvent? in
                guard let button = event.event.button else { return nil }
                return DebugOverlay.ClickEvent(
                    x: event.event.x,
                    y: event.event.y,
                    button: button,
                    isDown: event.event.type == .down,
                    timestamp: event.timelineTimestamp
                )
            }

        return DebugOverlay(
            cursorPositions: cursorPositions,
            clickEvents: clickEvents,
            timeRange: timeRange
        )
    }

    /// Validate telemetry synchronization without full sync
    /// - Parameters:
    ///   - telemetryFile: Path to cursor.jsonl file
    ///   - timeline: Timeline model from project
    ///   - config: Synchronization configuration
    /// - Returns: ValidationResult with validation status
    public func validate(
        telemetryFile: URL,
        timeline: Project.Timeline,
        config: Configuration = .default
    ) async throws -> ValidationResult {
        // Load telemetry events
        let events = try loadTelemetryEvents(from: telemetryFile)

        // Sync with timeline (minimal processing)
        let syncedEvents = try syncEventsWithTimeline(events, timeline: timeline)

        // Validate
        return validateSynchronization(syncedEvents, timeline: timeline, config: config)
    }

    // MARK: - Private Methods

    /// Load telemetry events from JSONL file
    private func loadTelemetryEvents(from url: URL) throws -> [TelemetryRecorder.Event] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.fileNotFound(url)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }

        var events: [TelemetryRecorder.Event] = []
        var parseErrors: [String] = []

        for (index, line) in lines.enumerated() {
            do {
                guard let data = line.data(using: .utf8) else {
                    parseErrors.append("Line \(index + 1): Failed to encode line to UTF-8")
                    continue
                }
                let decoder = JSONDecoder()
                let event = try decoder.decode(TelemetryRecorder.Event.self, from: data)
                events.append(event)
            } catch {
                parseErrors.append("Line \(index + 1): \(error.localizedDescription)")
            }
        }

        if !parseErrors.isEmpty && events.isEmpty {
            throw SyncError.parseError(parseErrors.joined(separator: "; "))
        }

        return events
    }

    /// Synchronize telemetry events with timeline segments
    private func syncEventsWithTimeline(
        _ events: [TelemetryRecorder.Event],
        timeline: Project.Timeline
    ) throws -> [SyncedEvent] {
        var syncedEvents: [SyncedEvent] = []

        for event in events {
            // Find which segment this event belongs to
            let segment = timeline.segments.first { segment in
                event.t >= segment.sourceIn && event.t <= segment.sourceOut
            }

            // Calculate timeline timestamp
            let timelineTimestamp: TimeInterval
            if let segment = segment {
                // Event is within a segment - map to timeline time
                let segmentOffset = event.t - segment.sourceIn
                timelineTimestamp = segment.timelineIn + (segmentOffset / segment.speed)
            } else {
                // Event is outside any segment - keep as-is (will be filtered later)
                timelineTimestamp = event.t
            }

            let syncedEvent = SyncedEvent(
                event: event,
                timelineTimestamp: timelineTimestamp,
                sourceTimestamp: event.t,
                segmentId: segment?.id
            )

            syncedEvents.append(syncedEvent)
        }

        return syncedEvents
    }

    /// Validate synchronization
    private func validateSynchronization(
        _ events: [SyncedEvent],
        timeline: Project.Timeline,
        config: Configuration
    ) -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var missingSegments: [MissingSegment] = []

        guard !events.isEmpty else {
            return ValidationResult(
                isValid: false,
                syncOffsetMs: 0,
                missingSegments: [],
                warnings: [ValidationWarning(type: .lowEventCount, message: "No telemetry events found")]
            )
        }

        // Check event count
        if Double(events.count) / timeline.duration < config.minExpectedEventsPerSecond {
            warnings.append(ValidationWarning(
                type: .lowEventCount,
                message: "Low event count: \(events.count) events over \(timeline.duration)s"
            ))
        }

        // Check for gaps in telemetry data
        if config.detectGaps {
            let sortedEvents = events.sorted { $0.sourceTimestamp < $1.sourceTimestamp }
            var previousTimestamp: TimeInterval?

            for event in sortedEvents {
                if let prev = previousTimestamp {
                    let gap = event.sourceTimestamp - prev
                    if gap >= config.minGapDuration {
                        missingSegments.append(MissingSegment(
                            startTime: prev,
                            endTime: event.sourceTimestamp
                        ))
                    }
                }
                previousTimestamp = event.sourceTimestamp
            }
        }

        // Check for irregular sampling (move events)
        let moveEvents = events.filter { $0.event.type == .move }
        if moveEvents.count > 1 {
            let sortedMoveEvents = moveEvents.sorted { $0.sourceTimestamp < $1.sourceTimestamp }
            var intervals: [TimeInterval] = []

            for i in 1..<sortedMoveEvents.count {
                let interval = sortedMoveEvents[i].sourceTimestamp - sortedMoveEvents[i-1].sourceTimestamp
                intervals.append(interval)
            }

            // Check variance in sampling intervals
            if let avgInterval = intervals.mean, let stdDev = intervals.standardDeviation {
                let coefficientOfVariation = stdDev / avgInterval
                if coefficientOfVariation > 0.5 {
                    warnings.append(ValidationWarning(
                        type: .irregularSampling,
                        message: "Irregular sampling detected: CV \(String(format: "%.2f", coefficientOfVariation))"
                    ))
                }
            }
        }

        // Check for missing click pairs (down without up)
        let clickDowns = events.filter { $0.event.type == .down }.count
        let clickUps = events.filter { $0.event.type == .up }.count
        if abs(clickDowns - clickUps) > 1 {
            warnings.append(ValidationWarning(
                type: .missingClickEvents,
                message: "Unbalanced click events: \(clickDowns) downs, \(clickUps) ups"
            ))
        }

        // Calculate sync offset (difference between first telemetry event and timeline start)
        let firstEventTime = events.map { $0.sourceTimestamp }.min() ?? 0
        let timelineStart = timeline.segments.first?.timelineIn ?? 0.0
        let syncOffsetMs = (firstEventTime - timelineStart) * 1000

        // Detect drift (simplified - compare expected vs actual timestamps at regular intervals)
        let drift = detectDrift(events: events, timeline: timeline, config: config)

        // Determine validity
        let isValid = abs(syncOffsetMs) < config.acceptableDriftMs &&
                      !(drift?.isExcessive ?? false) &&
                      missingSegments.filter { $0.duration >= 1.0 }.isEmpty

        return ValidationResult(
            isValid: isValid,
            syncOffsetMs: syncOffsetMs,
            drift: drift,
            missingSegments: missingSegments.filter { $0.duration >= config.minGapDuration },
            warnings: warnings
        )
    }

    /// Detect drift in telemetry timestamps
    private func detectDrift(
        events: [SyncedEvent],
        timeline: Project.Timeline,
        config: Configuration
    ) -> DriftInfo? {
        // Simplified drift detection: compare expected vs actual position at multiple points
        let samplePoints = 10
        let duration = timeline.duration
        let interval = duration / Double(samplePoints)

        var drifts: [Double] = []

        for i in 0...samplePoints {
            let expectedTime = Double(i) * interval

            // Find closest event
            if let closestEvent = events.min(by: { a, b in
                abs(a.timelineTimestamp - expectedTime) < abs(b.timelineTimestamp - expectedTime)
            }) {
                let drift = closestEvent.timelineTimestamp - expectedTime
                drifts.append(drift * 1000) // Convert to ms
            }
        }

        guard !drifts.isEmpty else { return nil }

        let maxDrift = drifts.map { abs($0) }.max() ?? 0
        let avgDrift = drifts.map { abs($0) }.reduce(0, +) / Double(drifts.count)
        let maxDriftIndex = drifts.map { abs($0) }.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let maxDriftTimestamp = Double(maxDriftIndex) * interval

        let isExcessive = maxDrift > config.acceptableDriftMs

        return DriftInfo(
            maxDriftMs: maxDrift,
            avgDriftMs: avgDrift,
            maxDriftTimestamp: maxDriftTimestamp,
            isExcessive: isExcessive
        )
    }

    /// Calculate synchronization statistics
    private func calculateStatistics(
        for events: [SyncedEvent],
        timeline: Project.Timeline
    ) -> SyncStats {
        let moveEvents = events.filter { $0.event.type == .move }
        let clickEvents = events.filter { $0.event.type == .down || $0.event.type == .up }
        let scrollEvents = events.filter { $0.event.type == .scroll }

        let eventsPerSecond = events.isEmpty ? 0 : Double(events.count) / timeline.duration

        let timeRange: ClosedRange<TimeInterval>
        if let minTime = events.map({ $0.sourceTimestamp }).min(),
           let maxTime = events.map({ $0.sourceTimestamp }).max() {
            timeRange = minTime...maxTime
        } else {
            timeRange = 0...0
        }

        return SyncStats(
            totalEvents: events.count,
            moveEvents: moveEvents.count,
            clickEvents: clickEvents.count,
            scrollEvents: scrollEvents.count,
            eventsPerSecond: eventsPerSecond,
            timeRange: timeRange
        )
    }
}
