//
//  TelemetryOverlayView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit
import CoreGraphics

/// View that renders telemetry overlays (cursor, clicks, keystrokes) on top of video preview
struct TelemetryOverlayView: View {
    let project: Project?
    let projectDirectory: URL?
    let currentTime: TimeInterval
    let showCursor: Bool
    let showClicks: Bool
    let showKeystrokes: Bool
    let overlaySize: CoreGraphics.CGSize

    @State private var cursorEvents: [TelemetrySync.SyncedEvent] = []
    @State private var clickEvents: [TelemetrySync.SyncedEvent] = []
    @State private var keystrokeEvents: [KeystrokeRecorder.Event] = []
    @State private var overlayData: TelemetrySync.DebugOverlay?

    var body: some View {
        ZStack {
            // Cursor visualization
            if showCursor, let cursorPos = currentCursorPosition {
                cursorView(at: cursorPos)
            }

            // Click visualization
            if showClicks {
                ForEach(visibleClickEvents, id: \.id) { event in
                    clickView(for: event)
                }
            }

            // Keystroke visualization
            if showKeystrokes {
                ForEach(visibleKeystrokeEvents, id: \.t) { event in
                    keystrokeView(for: event)
                }
            }
        }
        .onAppear {
            Task {
                await loadTelemetryData()
            }
        }
        .onChange(of: project?.projectId) { _ in
            Task {
                await loadTelemetryData()
            }
        }
    }

    // MARK: - Cursor View

    @ViewBuilder
    private func cursorView(at position: TelemetrySync.DebugOverlay.CursorPosition) -> some View {
        GeometryReader { geometry in
            let normalizedPos = normalizePosition(
                x: position.x,
                y: position.y,
                in: geometry.size
            )

            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .position(x: normalizedPos.x, y: normalizedPos.y)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
        }
    }

    // MARK: - Click View

    @ViewBuilder
    private func clickView(for event: TelemetrySync.SyncedEvent) -> some View {
        let clickEvent = event.event

        GeometryReader { geometry in
            let normalizedPos = normalizePosition(
                x: clickEvent.x,
                y: clickEvent.y,
                in: geometry.size
            )

            let isMouseDown = clickEvent.type == .down

            ZStack {
                // Outer ripple
                Circle()
                    .stroke(isMouseDown ? Color.red : Color.blue, lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .opacity(clickOpacity(for: event))

                // Inner dot
                Circle()
                    .fill(isMouseDown ? Color.red : Color.blue)
                    .frame(width: 8, height: 8)
            }
            .position(x: normalizedPos.x, y: normalizedPos.y)
            .animation(.easeOut(duration: 0.5), value: currentTime)
        }
    }

    // MARK: - Keystroke View

    @ViewBuilder
    private func keystrokeView(for event: KeystrokeRecorder.Event) -> some View {
        VStack(spacing: 4) {
            // Modifiers display
            if event.modifiers.isActive() {
                Text(event.modifiers.description())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Key display
            if !event.characters.isEmpty {
                Text(displayKey(for: event))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .transition(.opacity)
        .animation(.easeOut(duration: 0.3), value: currentTime)
        .position(x: overlaySize.width / 2, y: 60)
    }

    // MARK: - Helper Methods

    private var currentCursorPosition: TelemetrySync.DebugOverlay.CursorPosition? {
        guard showCursor,
              let overlay = overlayData else {
            return nil
        }

        return overlay.cursorPosition(at: currentTime)
    }

    private var visibleClickEvents: [TelemetrySync.SyncedEvent] {
        guard showClicks else { return [] }

        let clickWindow: TimeInterval = 1.0 // Show clicks for 1 second
        let visibleRange = (currentTime - clickWindow)...(currentTime + clickWindow)

        return clickEvents.filter { event in
            visibleRange.contains(event.timelineTimestamp)
        }
    }

    private var visibleKeystrokeEvents: [KeystrokeRecorder.Event] {
        guard showKeystrokes else { return [] }

        let keystrokeWindow: TimeInterval = 2.0 // Show keystrokes for 2 seconds
        let visibleRange = (currentTime - keystrokeWindow)...currentTime

        return keystrokeEvents.filter { event in
            visibleRange.contains(event.t)
        }
    }

    private func clickOpacity(for event: TelemetrySync.SyncedEvent) -> Double {
        let age = abs(currentTime - event.timelineTimestamp)
        let maxAge: TimeInterval = 1.0
        return max(0, 1.0 - (age / maxAge))
    }

    private func normalizePosition(x: Int, y: Int, in size: CoreGraphics.CGSize) -> CoreGraphics.CGPoint {
        // Assume source is 1920x1080 for now
        // In production, this should use project.sources.screen.size
        let sourceWidth: CoreGraphics.CGFloat = 1920
        let sourceHeight: CoreGraphics.CGFloat = 1080

        let normalizedX = (CoreGraphics.CGFloat(x) / sourceWidth) * size.width
        let normalizedY = (CoreGraphics.CGFloat(y) / sourceHeight) * size.height

        return CoreGraphics.CGPoint(x: normalizedX, y: normalizedY)
    }

    private func displayKey(for event: KeystrokeRecorder.Event) -> String {
        if let chars = event.characters {
            // Format special keys
            let specialKeys: [String: String] = [
                " ": "Space",
                "\r": "Return",
                "\t": "Tab",
                "\u{7F}": "Delete",
                "\u{1B}": "Escape"
            ]

            if let special = specialKeys[chars] {
                return special
            }

            return chars.uppercased()
        }

        return ""
    }

    // MARK: - Data Loading

    private func loadTelemetryData() async {
        guard let project,
              let projectDirectory else {
            return
        }

        // Load cursor telemetry
        if let cursorTrack = project.sources.telemetry?.cursor {
            await loadCursorTelemetry(
                from: projectDirectory.appendingPathComponent(cursorTrack.path),
                project: project
            )
        }

        // Load keystroke telemetry
        if let keysTrack = project.sources.telemetry?.keys {
            await loadKeystrokeTelemetry(
                from: projectDirectory.appendingPathComponent(keysTrack.path)
            )
        }
    }

    private func loadCursorTelemetry(from url: URL, project: Project) async {
        let telemetrySync = TelemetrySync()

        do {
            let result = try await telemetrySync.synchronize(
                telemetryFile: url,
                timeline: project.timeline
            )

            // Separate events by type
            cursorEvents = result.events.filter { $0.event.type == .move }
            clickEvents = result.events.filter { $0.event.type == .down || $0.event.type == .up }

            // Create overlay data for cursor interpolation
            let timeRange: ClosedRange<TimeInterval> = 0...project.timeline.duration
            let debugOverlay = await telemetrySync.createDebugOverlay(
                syncedEvents: result.events,
                timeRange: timeRange
            )
            overlayData = debugOverlay
        } catch {
            // Silently fail if telemetry is not available
            print("Failed to load cursor telemetry: \(error.localizedDescription)")
        }
    }

    private func loadKeystrokeTelemetry(from url: URL) async {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.split(separator: "\n").filter { !$0.isEmpty }

            var events: [KeystrokeRecorder.Event] = []

            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                let decoder = JSONDecoder()
                if let event = try? decoder.decode(KeystrokeRecorder.Event.self, from: data) {
                    events.append(event)
                }
            }

            await MainActor.run {
                keystrokeEvents = events
            }
        } catch {
            // Silently fail if keystroke telemetry is not available
            print("Failed to load keystroke telemetry: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview {
    TelemetryOverlayView(
        project: nil as Project?,
        projectDirectory: nil as URL?,
        currentTime: 5.0,
        showCursor: true,
        showClicks: true,
        showKeystrokes: true,
        overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
    )
}
