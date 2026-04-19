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

            if !suggestions.isEmpty {
                if let plan = try? await generator.applyAsPlan(suggestions) {
                    await playerViewModel.previewEngine?.setZoomPlan(plan)
                    LogInfo(.telemetry, "Auto-applied zoom plan with \(plan.keyframes.count) keyframes")
                }
            }

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
                await playerViewModel.previewEngine?.setZoomPlan(plan)
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
            updatedProject.timeline.segments[i].zoom = zoomConfig
        }
        await editor.setProject(updatedProject)
    }
}

struct ZoomSuggestionGenerator {
    let project: Project
    let projectDirectory: URL?
    
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
        var parseResult: TelemetryParser.ParseResult?
        var events: [TelemetryRecorder.Event]
        
        do {
            let result = try await parser.parse(telemetryFile: cursorURL)
            parseResult = result
            LogDebug(.telemetry, "Parser found \(result.importantClicks.count) clicks, \(result.windows.count) windows")
            
            let data = try String(contentsOf: cursorURL, encoding: .utf8)
            let decoder = JSONDecoder()
            events = data.split(separator: "\n").compactMap { line in
                try? decoder.decode(TelemetryRecorder.Event.self, from: Data(line.utf8))
            }
            LogDebug(.telemetry, "Decoded \(events.count) raw events")
        } catch {
            LogError(.telemetry, "Parse error: \(error.localizedDescription)")
            parseResult = nil
            events = []
        }
        
        guard !events.isEmpty else {
            LogWarning(.telemetry, "No events — aborting zoom suggestion generation")
            return []
        }
        
        let emptyStats = TelemetryParser.ParseStats(
            totalEvents: events.count, totalClicks: 0, importantClickCount: 0,
            windowCount: 0, clicksPerSecond: 0, timeRange: 0...project.timeline.duration
        )
        let result = parseResult ?? TelemetryParser.ParseResult(
            importantClicks: [], windows: [], stats: emptyStats
        )
        
        let suggestions = ZoomSuggestionEngine.generateSuggestions(
            events: events,
            parseResult: result,
            screenWidth: Double(project.canvas.format.w),
            screenHeight: Double(project.canvas.format.h),
            timelineDuration: project.timeline.duration
        )
        
        LogInfo(.telemetry, "Generated \(suggestions.count) zoom suggestions")
        return suggestions
    }
    
    func applyAsPlan(_ suggestions: [ZoomSuggestion]) async throws -> ZoomPlanGenerator.ZoomPlan {
        try await ZoomSuggestionEngine.applyAsPlan(
            suggestions: suggestions,
            screenWidth: Double(project.canvas.format.w),
            screenHeight: Double(project.canvas.format.h),
            timelineDuration: project.timeline.duration
        )
    }
}
