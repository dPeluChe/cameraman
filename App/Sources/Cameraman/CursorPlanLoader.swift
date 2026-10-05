//
//  CursorPlanLoader.swift
//  App
//
//  Loads cursor telemetry and builds a CursorPlan for synthetic cursor rendering.
//

import EngineKit
import Foundation

enum CursorPlanLoader {
    /// Build a CursorPlan from the project's cursor telemetry, rebased into
    /// capture-local space via CaptureGeometry. Returns nil when telemetry is
    /// missing, the cursor feature is disabled, or no events survive rebasing.
    private static let cache = PlanCache()

    /// Keeps only the latest plan; switching projects replaces it.
    private final class PlanCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entry: (key: String, plan: CursorPlan)?
        func value(for key: String) -> CursorPlan? {
            lock.lock(); defer { lock.unlock() }
            return entry?.key == key ? entry?.plan : nil
        }
        func store(_ plan: CursorPlan, for key: String) {
            lock.lock(); defer { lock.unlock() }
            entry = (key, plan)
        }
    }

    static func loadCursorPlan(
        for project: Project,
        projectDirectory: URL?
    ) async -> CursorPlan? {
        guard project.syntheticCursor?.enabled == true else { return nil }
        guard let projectDirectory else {
            LogDebug(.telemetry, "No project directory for synthetic cursor")
            return nil
        }
        guard let cursorTrack = project.primarySources?.telemetry?.cursor else {
            LogDebug(.telemetry, "No cursor telemetry for synthetic cursor")
            return nil
        }

        let cursorURL = projectDirectory.appendingPathComponent(cursorTrack.path)
        let geometry = await MainActor.run { resolveGeometry(for: project) }
        let dims = geometry.map { ($0.rect.w, $0.rect.h) } ?? { let d = fallbackDimensions(for: project); return (d.width, d.height) }()

        // Edits re-enter here on every change; the plan only depends on the file and geometry.
        let attrs = try? FileManager.default.attributesOfItem(atPath: cursorURL.path)
        let cacheKey = "\(cursorURL.path)|\(attrs?[.modificationDate] ?? "")|\(attrs?[.size] ?? "")|\(String(describing: geometry?.rect))|\(dims.0)x\(dims.1)"
        if let hit = cache.value(for: cacheKey) { return hit }

        let parser = TelemetryParser()

        var rawEvents: [TelemetryRecorder.Event] = []
        do {
            rawEvents = try await parser.loadEvents(from: cursorURL)
            LogDebug(.telemetry, "Loaded \(rawEvents.count) cursor events for synthetic cursor")
        } catch {
            LogError(.telemetry, "Failed to load cursor telemetry: \(error.localizedDescription)")
            return nil
        }

        guard !rawEvents.isEmpty else {
            LogDebug(.telemetry, "No cursor events loaded for synthetic cursor")
            return nil
        }

        let prepared: (events: [TelemetryRecorder.Event], width: Double, height: Double)
        if let geometry {
            prepared = (geometry.rebaseToCaptureSpace(rawEvents), geometry.rect.w, geometry.rect.h)
            LogDebug(.telemetry, "Synthetic cursor: loaded \(rawEvents.count) raw events, \(prepared.events.count) inside capture region \(geometry.rect)")
        } else {
            prepared = (rawEvents, dims.0, dims.1)
            LogDebug(.telemetry, "Synthetic cursor: no capture geometry, using fallback \(dims.0)x\(dims.1)")
        }

        guard prepared.width > 0, prepared.height > 0 else { return nil }

        let plan = CursorPlanGenerator.generate(
            from: prepared.events,
            screenWidth: prepared.width,
            screenHeight: prepared.height
        )
        LogDebug(.telemetry, "Synthetic cursor plan: \(plan.samples.count) samples, \(plan.clicks.count) clicks")
        cache.store(plan, for: cacheKey)
        return plan
    }

    /// Capture geometry from the primary screen source, or inferred from the
    /// attached displays for legacy full-display recordings.
    @MainActor
    private static func resolveGeometry(for project: Project) -> CaptureGeometry? {
        if let geometry = project.primarySources?.screen.capture {
            return geometry
        }
        if let size = project.primarySources?.screen.size {
            return CaptureGeometry.inferred(pixelWidth: size.w, pixelHeight: size.h)
        }
        return nil
    }

    /// Fallback dimensions when no capture geometry is available.
    private static func fallbackDimensions(for project: Project) -> (width: Double, height: Double) {
        if let size = project.primarySources?.screen.size {
            return (Double(size.w), Double(size.h))
        }
        return (Double(project.canvas.format.w), Double(project.canvas.format.h))
    }
}
