//
//  TimelineView+ZoomSuggestions.swift
//  App
//
//  Extracted from TimelineView.swift
//  Zoom suggestion generation and application
//

import SwiftUI
import EngineKit

extension TimelineView {
    var hasCursorTelemetry: Bool {
        project.primarySources?.telemetry?.cursor != nil
    }

    var activeSuggestions: [ZoomSuggestion] {
        zoomSuggestions.filter { !dismissedSuggestionIds.contains($0.id) }
    }

    func generateZoomSuggestions() {
        guard hasCursorTelemetry, let projDir = projectDirectory else {
            LogDebug(.telemetry, "No cursor telemetry or project directory")
            return
        }

        isGeneratingSuggestions = true

        Task {
            let generator = ZoomSuggestionGenerator(project: project, projectDirectory: projDir)
            let suggestions = await generator.generate()

            // Suggestions only mark the timeline — the user opts in via Apply.
            // (Auto-applying the plan on open confused testers.)
            await MainActor.run {
                zoomSuggestions = suggestions
                isGeneratingSuggestions = false
            }
        }
    }

    func applyZoomSuggestions() {
        let suggestions = activeSuggestions
        guard !suggestions.isEmpty else { return }

        Task {
            let generator = ZoomSuggestionGenerator(project: project, projectDirectory: projectDirectory)
            if let plan = try? await generator.applyAsPlan(suggestions) {
                await MainActor.run { playerViewModel.setZoomPlan(plan) }
            }

            await enableZoomOnAllSegments()

            await MainActor.run {
                zoomSuggestions = []
                dismissedSuggestionIds = []
            }
        }
    }

    private func enableZoomOnAllSegments() async {
        let zoomConfig = Project.Timeline.ZoomConfiguration(
            enabled: true,
            intensity: .normal
        )
        var updatedProject = editor.project
        for i in updatedProject.timeline.segments.indices {
            // Preserve segments the user explicitly disabled. Treat a missing
            // config (nil) as "unset" → safe to apply the default.
            if updatedProject.timeline.segments[i].zoom?.enabled == false { continue }
            updatedProject.timeline.segments[i].zoom = zoomConfig
        }
        await editor.setProject(updatedProject)
    }
}

struct ZoomSuggestionGenerator {
    let project: Project
    let projectDirectory: URL?

    /// Legacy fallback dimensions: recorded video PIXELS. Only used when no capture
    /// geometry is available (window/app captures, or old recordings on unknown
    /// displays) — on Retina screens this mismatches the telemetry point space,
    /// which is exactly what CaptureGeometry persistence fixes.
    private var captureDimensions: (width: Double, height: Double) {
        if let size = project.primarySources?.screen.size {
            return (Double(size.w), Double(size.h))
        }
        return (Double(project.canvas.format.w), Double(project.canvas.format.h))
    }

    /// Capture geometry: persisted with the recording when available; inferred
    /// from the attached displays for legacy full-display recordings.
    @MainActor
    private func resolveGeometry() -> CaptureGeometry? {
        if let geometry = project.primarySources?.screen.capture {
            return geometry
        }
        if let size = project.primarySources?.screen.size {
            return CaptureGeometry.inferred(pixelWidth: size.w, pixelHeight: size.h)
        }
        return nil
    }

    /// Rebase raw telemetry events into capture-local space and return the matching
    /// screen dimensions (capture points). Falls back to raw events + pixel dims
    /// when no geometry is available (pre-geometry behavior).
    private func prepareEvents(
        _ events: [TelemetryRecorder.Event]
    ) async -> (events: [TelemetryRecorder.Event], width: Double, height: Double) {
        if let geometry = resolveGeometry() {
            return (geometry.rebaseToCaptureSpace(events), geometry.rect.w, geometry.rect.h)
        }
        let dims = captureDimensions
        return (events, dims.width, dims.height)
    }

    var hasCursorTelemetry: Bool {
        project.primarySources?.telemetry?.cursor != nil
    }

    var activeSuggestions: [ZoomSuggestion] {
        []
    }

    func generate() async -> [ZoomSuggestion] {
        guard let cursorTrack = project.primarySources?.telemetry?.cursor,
              let projDir = projectDirectory else {
            LogDebug(.telemetry, "No cursor telemetry or project directory")
            return []
        }

        let cursorURL = projDir.appendingPathComponent(cursorTrack.path)
        LogDebug(.telemetry, "Loading telemetry from: \(cursorURL.path)")

        let parser = TelemetryParser()
        var rawEvents: [TelemetryRecorder.Event] = []
        do {
            rawEvents = try await parser.loadEvents(from: cursorURL)
            LogDebug(.telemetry, "Decoded \(rawEvents.count) raw events")
        } catch {
            LogError(.telemetry, "Telemetry load error: \(error.localizedDescription)")
        }

        guard !rawEvents.isEmpty else {
            LogWarning(.telemetry, "No events — aborting zoom suggestion generation")
            return []
        }

        // Rebase events into capture space BEFORE parsing so click windows,
        // dwell centroids, and focus normalization all share one coordinate space.
        let prepared = await prepareEvents(rawEvents)
        if prepared.events.count != rawEvents.count {
            LogDebug(.telemetry, "Dropped \(rawEvents.count - prepared.events.count) events outside the capture region")
        }

        var parseResult: TelemetryParser.ParseResult?
        do {
            let result = try await parser.parseEvents(prepared.events)
            parseResult = result
            LogDebug(.telemetry, "Parser found \(result.importantClicks.count) clicks, \(result.windows.count) windows")
        } catch {
            LogError(.telemetry, "Parse error: \(error.localizedDescription)")
        }

        let emptyStats = TelemetryParser.ParseStats(
            totalEvents: prepared.events.count, totalClicks: 0, importantClickCount: 0,
            windowCount: 0, clicksPerSecond: 0, timeRange: 0...project.timeline.duration
        )
        let result = parseResult ?? TelemetryParser.ParseResult(
            importantClicks: [], windows: [], stats: emptyStats
        )

        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: prepared.events,
            parseResult: result,
            screenWidth: prepared.width,
            screenHeight: prepared.height,
            timelineDuration: project.timeline.duration
        )

        LogInfo(.telemetry, "Generated \(suggestions.count) zoom suggestions (capture space \(Int(prepared.width))x\(Int(prepared.height)))")
        return suggestions
    }

    func applyAsPlan(_ suggestions: [ZoomSuggestion]) async throws -> ZoomPlanGenerator.ZoomPlan {
        // Suggestions carry normalized focus; the dims only shape the round-trip
        // through ClickWindow — they must match the space generate() used.
        let dims: (width: Double, height: Double)
        if let geometry = resolveGeometry() {
            dims = (geometry.rect.w, geometry.rect.h)
        } else {
            dims = captureDimensions
        }
        return try await ZoomSuggestionEngine.applyAsPlan(
            suggestions: suggestions,
            screenWidth: dims.width,
            screenHeight: dims.height,
            timelineDuration: project.timeline.duration
        )
    }
}
