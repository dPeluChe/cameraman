//
//  TimelineView+ZoomSuggestions.swift
//  App
//
//  Extracted from TimelineView.swift
//  Zoom suggestion generation and application
//

import SwiftUI
import EngineKit

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
