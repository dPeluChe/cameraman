//
//  TimelineView.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI
import EngineKit

/// Timeline UI for video editing
/// Supports range selection, split, and delete operations
struct TimelineView: View {
    // Project and Editor
    @ObservedObject var projectEditor: ProjectEditor

    // View State
    @State private var selectionRange: RangeSelection?
    @State private var hoveredSegment: String?
    @State private var isDragging = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var playheadPosition: TimeInterval = 0

    // Layout Constants
    private let trackHeight: CGFloat = 60
    private let timelineHeight: CGFloat = 100
    private let playheadWidth: CGFloat = 2
    private let minSelectionWidth: CGFloat = 5

    var body: some View {
        VStack(spacing: 0) {
            // Time ruler
            timeRuler
                .frame(height: 20)

            // Timeline tracks
            ScrollView([.horizontal], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Tracks
                    VStack(spacing: 4) {
                        // Screen track
                        trackView(
                            title: "Screen",
                            color: Color.blue.opacity(0.6),
                            segments: projectEditor.project.timeline.segments
                        )

                        // Camera track (if available)
                        if projectEditor.project.sources.camera != nil {
                            trackView(
                                title: "Camera",
                                color: Color.green.opacity(0.6),
                                segments: projectEditor.project.timeline.segments
                            )
                        }

                        // Audio tracks (if available)
                        if projectEditor.project.sources.audio != nil {
                            if projectEditor.project.sources.audio?.system != nil {
                                trackView(
                                    title: "System Audio",
                                    color: Color.purple.opacity(0.6),
                                    segments: projectEditor.project.timeline.segments
                                )
                            }
                            if projectEditor.project.sources.audio?.mic != nil {
                                trackView(
                                    title: "Mic Audio",
                                    color: Color.orange.opacity(0.6),
                                    segments: projectEditor.project.timeline.segments
                                )
                            }
                        }
                    }
                    .padding(.leading, 150) // Space for track labels
                    .padding(.trailing, 20)

                    // Playhead
                    playheadOverlay
                }
                .frame(height: timelineHeight)
                .background(Color.black.opacity(0.3))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value)
                        }
                        .onEnded { value in
                            handleDragEnded(value)
                        }
                )
            }

            // Toolbar
            toolbar
        }
        .frame(height: timelineHeight + 20 + 40) // tracks + ruler + toolbar
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Time Ruler

    private var timeRuler: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, timelineWidth(for: projectEditor.project.timeline.duration))
            let duration = projectEditor.project.timeline.duration

            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.gray.opacity(0.2))

                // Time markers
                ForEach(0..<Int(ceil(duration)) + 1, id: \.self) { second in
                    let xPosition = timeToX(second, inWidth: width)

                    VStack(alignment: .leading, spacing: 0) {
                        // Major tick
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 1, height: 8)

                        // Time label
                        Text(formatTime(second))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .position(x: xPosition, y: 10)
                }

                // Minor ticks (every 0.5 seconds)
                ForEach(0..<Int(ceil(duration * 2)), id: \.self) { halfSecond in
                    if halfSecond % 2 != 0 {
                        let xPosition = timeToX(TimeInterval(halfSecond) / 2, inWidth: width)

                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 1, height: 4)
                            .position(x: xPosition, y: 10)
                    }
                }
            }
            .padding(.leading, 150)
            .padding(.trailing, 20)
        }
        .frame(height: 20)
    }

    // MARK: - Track View

    private func trackView(title: String, color: Color, segments: [Project.Timeline.Segment]) -> some View {
        GeometryReader { geometry in
            let width = timelineWidth(for: projectEditor.project.timeline.duration)

            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(color.opacity(0.2))
                    .frame(height: trackHeight)

                // Track label
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Segments
                ForEach(segments) { segment in
                    let segmentWidth = timeToX(segment.timelineDuration, inWidth: width)
                    let xPosition = timeToX(segment.timelineIn, inWidth: width)

                    segmentRect(segment, width: segmentWidth, color: color)
                        .position(x: xPosition + segmentWidth / 2, y: trackHeight / 2)
                        .opacity(
                            hoveredSegment == segment.id || isSegmentSelected(segment) ? 0.8 : 1.0
                        )
                        .overlay(
                            // Selection highlight
                            Rectangle()
                                .stroke(Color.white, lineWidth: isSegmentSelected(segment) ? 2 : 0)
                        )
                        .onHover { hovering in
                            hoveredSegment = hovering ? segment.id : nil
                        }
                }
            }
        }
        .frame(height: trackHeight)
    }

    private func segmentRect(_ segment: Project.Timeline.Segment, width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(
                // Segment duration label
                Text("\(segment.timelineDuration, specifier: "%.1f")s")
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(2)
            )
    }

    // MARK: - Playhead Overlay

    private var playheadOverlay: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, timelineWidth(for: projectEditor.project.timeline.duration))
            let xPosition = timeToX(playheadPosition, inWidth: width)

            ZStack {
                // Playhead line
                Rectangle()
                    .fill(Color.red)
                    .frame(width: playheadWidth, height: .infinity)

                // Playhead handle
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .offset(y: -6)
            }
            .position(x: xPosition + playheadWidth / 2, y: timelineHeight / 2)
            .padding(.leading, 150)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if let selection = selectionRange {
            GeometryReader { geometry in
                let width = max(geometry.size.width, timelineWidth(for: projectEditor.project.timeline.duration))
                let startX = timeToX(selection.startTime, inWidth: width)
                let endX = timeToX(selection.endTime, inWidth: width)

                Rectangle()
                    .fill(Color.yellow.opacity(0.3))
                    .frame(width: endX - startX, height: timelineHeight)
                    .position(x: startX + (endX - startX) / 2, y: timelineHeight / 2)
                    .padding(.leading, 150)
                    .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Time display
            Text(formatTime(playheadPosition))
                .font(.system(.monospacedDigit, size: 12))
                .foregroundColor(.secondary)
                .frame(minWidth: 60)

            Divider()
                .frame(height: 20)

            // Split button
            Button(action: splitSelectedSegment) {
                Label("Split", systemImage: "scissors")
                    .font(.system(size: 11))
            }
            .disabled(selectionRange == nil || !hasSingleSelectedSegment)
            .help("Split segment at playhead position")

            // Delete button
            Button(action: deleteSelection) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .disabled(selectionRange == nil)
            .help("Delete selected range")

            // Trim in button
            Button(action: trimInSelection) {
                Label("Trim In", systemImage: "line.diagonal.from.bottom.left.to.top.right")
                    .font(.system(size: 11))
            }
            .disabled(selectionRange == nil || !hasSingleSelectedSegment)
            .help("Trim beginning of selected segment")

            // Trim out button
            Button(action: trimOutSelection) {
                Label("Trim Out", systemImage: "line.diagonal.from.top.left.to.bottom.right")
                    .font(.system(size: 11))
            }
            .disabled(selectionRange == nil || !hasSingleSelectedSegment)
            .help("Trim end of selected segment")

            Spacer()

            // Clear selection button
            if selectionRange != nil {
                Button(action: clearSelection) {
                    Text("Clear Selection")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Helper Methods

    private func timelineWidth(for duration: TimeInterval) -> CGFloat {
        // Scale: 1 second = 50 pixels (adjustable)
        let pixelsPerSecond: CGFloat = 50
        return CGFloat(duration) * pixelsPerSecond
    }

    private func timeToX(_ time: TimeInterval, inWidth width: CGFloat) -> CGFloat {
        let duration = projectEditor.project.timeline.duration
        let pixelsPerSecond = width / CGFloat(duration)
        return CGFloat(time) * pixelsPerSecond
    }

    private func xToTime(_ x: CGFloat, inWidth width: CGFloat) -> TimeInterval {
        let duration = projectEditor.project.timeline.duration
        let pixelsPerSecond = width / CGFloat(duration)
        return TimeInterval(x) / pixelsPerSecond
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 30) // Assuming 30fps
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }

    private func isSegmentSelected(_ segment: Project.Timeline.Segment) -> Bool {
        guard let selection = selectionRange else { return false }
        return segment.timelineIn >= selection.startTime &&
               segment.timelineOut <= selection.endTime
    }

    private var hasSingleSelectedSegment: Bool {
        guard let selection = selectionRange else { return false }
        let selectedSegments = projectEditor.project.timeline.segments.filter { segment in
            segment.timelineIn >= selection.startTime &&
            segment.timelineOut <= selection.endTime
        }
        return selectedSegments.count == 1
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !isDragging else {
            // Update selection range while dragging
            if let selection = selectionRange {
                let currentPoint = value.location
                let startTime = min(dragStartPoint.x, currentPoint.x)
                let endTime = max(dragStartPoint.x, currentPoint.x)

                // Convert to timeline time
                let width = timelineWidth(for: projectEditor.project.timeline.duration)
                let startTimelineTime = xToTime(startTime - 150, inWidth: width) // Adjust for label padding
                let endTimelineTime = xToTime(endTime - 150, inWidth: width)

                selectionRange = RangeSelection(
                    startTime: max(0, startTimelineTime),
                    endTime: min(projectEditor.project.timeline.duration, endTimelineTime)
                )
            }
            return
        }

        // Start new selection
        isDragging = true
        dragStartPoint = value.location

        // Convert start point to timeline time
        let width = timelineWidth(for: projectEditor.project.timeline.duration)
        let startTime = xToTime(value.location.x - 150, inWidth: width) // Adjust for label padding

        // Update playhead position
        playheadPosition = max(0, min(projectEditor.project.timeline.duration, startTime))
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        isDragging = false

        // Create selection if drag was significant
        let dragDistance = hypot(value.location.x - dragStartPoint.x, value.location.y - dragStartPoint.y)
        if dragDistance > minSelectionWidth {
            // Range selection already created in handleDragChanged
        } else {
            // Click to place playhead, clear selection
            clearSelection()
        }
    }

    // MARK: - Edit Operations

    private func splitSelectedSegment() {
        guard let selection = selectionRange,
              let segment = projectEditor.project.timeline.segments.first(where: { isSegmentSelected($0) }) else {
            return
        }

        Task {
            let result = await projectEditor.split(segmentId: segment.id, at: selection.startTime)
            await handleEditorResult(result)
        }

        clearSelection()
    }

    private func deleteSelection() {
        guard let selection = selectionRange else { return }

        Task {
            let result = await projectEditor.deleteRange(from: selection.startTime, to: selection.endTime)
            await handleEditorResult(result)
        }

        clearSelection()
    }

    private func trimInSelection() {
        guard let selection = selectionRange,
              let segment = projectEditor.project.timeline.segments.first(where: { isSegmentSelected($0) }) else {
            return
        }

        Task {
            // Calculate new sourceIn time based on selection start
            let timelineOffset = selection.startTime - segment.timelineIn
            let newSourceIn = segment.sourceIn + timelineOffset

            let result = await projectEditor.trimIn(segmentId: segment.id, newSourceIn: newSourceIn)
            await handleEditorResult(result)
        }

        clearSelection()
    }

    private func trimOutSelection() {
        guard let selection = selectionRange,
              let segment = projectEditor.project.timeline.segments.first(where: { isSegmentSelected($0) }) else {
            return
        }

        Task {
            // Calculate new sourceOut time based on selection end
            let timelineOffset = selection.endTime - segment.timelineIn
            let newSourceOut = segment.sourceIn + timelineOffset

            let result = await projectEditor.trimOut(segmentId: segment.id, newSourceOut: newSourceOut)
            await handleEditorResult(result)
        }

        clearSelection()
    }

    private func clearSelection() {
        selectionRange = nil
    }

    private func handleEditorResult(_ result: EditorResult) async {
        switch result {
        case .success(let project):
            await MainActor.run {
                projectEditor.project = project
            }
        case .successWithInfo(let project, _):
            await MainActor.run {
                projectEditor.project = project
            }
        case .failure(let error):
            await MainActor.run {
                // TODO: Show error to user
                print("Editor error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Selection Model

struct RangeSelection {
    var startTime: TimeInterval
    var endTime: TimeInterval

    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - Project Editor

@MainActor
class ProjectEditor: ObservableObject {
    @Published var project: Project

    init(project: Project) {
        self.project = project
    }

    // MARK: - Editor Operations

    func trimIn(segmentId: String, newSourceIn: TimeInterval) async -> EditorResult {
        let editor = EditorModel(project: project)
        let result = await editor.trimIn(segmentId: segmentId, newSourceIn: newSourceIn)

        if case .success(let newProject) = result,
              case .successWithInfo(let newProject, _) = result {
            self.project = newProject
        }

        return result
    }

    func trimOut(segmentId: String, newSourceOut: TimeInterval) async -> EditorResult {
        let editor = EditorModel(project: project)
        let result = await editor.trimOut(segmentId: segmentId, newSourceOut: newSourceOut)

        if case .success(let newProject) = result,
              case .successWithInfo(let newProject, _) = result {
            self.project = newProject
        }

        return result
    }

    func split(segmentId: String, at timelineTime: TimeInterval) async -> EditorResult {
        let editor = EditorModel(project: project)
        let result = await editor.split(segmentId: segmentId, at: timelineTime)

        if case .success(let newProject) = result,
              case .successWithInfo(let newProject, _) = result {
            self.project = newProject
        }

        return result
    }

    func delete(segmentId: String) async -> EditorResult {
        let editor = EditorModel(project: project)
        let result = await editor.delete(segmentId: segmentId)

        if case .success(let newProject) = result,
              case .successWithInfo(let newProject, _) = result {
            self.project = newProject
        }

        return result
    }

    func deleteRange(from startTime: TimeInterval, to endTime: TimeInterval) async -> EditorResult {
        let editor = EditorModel(project: project)
        let result = await editor.deleteRange(from: startTime, to: endTime)

        if case .success(let newProject) = result,
              case .successWithInfo(let newProject, _) = result {
            self.project = newProject
        }

        return result
    }
}

// MARK: - Preview

#Preview {
    TimelineView(projectEditor: ProjectEditor(project: createSampleProject()))
}

private func createSampleProject() -> Project {
    let segment1 = Project.Timeline.Segment(
        id: "seg-1",
        sourceIn: 0.0,
        sourceOut: 10.0,
        timelineIn: 0.0,
        speed: 1.0
    )

    let segment2 = Project.Timeline.Segment(
        id: "seg-2",
        sourceIn: 10.0,
        sourceOut: 25.0,
        timelineIn: 10.0,
        speed: 1.0
    )

    let segment3 = Project.Timeline.Segment(
        id: "seg-3",
        sourceIn: 25.0,
        sourceOut: 35.0,
        timelineIn: 25.0,
        speed: 1.0
    )

    let timeline = Project.Timeline(
        duration: 35.0,
        segments: [segment1, segment2, segment3]
    )

    let sources = Project.Sources(
        syncReference: "screen",
        screen: Project.Sources.MediaTrack(
            path: "sources/screen.mov",
            fps: 60.0,
            size: Project.Sources.Size(w: 1920, h: 1080),
            syncOffsetMs: 0,
            sha256: "abc123",
            sizeBytes: 524288000
        ),
        camera: Project.Sources.MediaTrack(
            path: "sources/camera.mov",
            fps: 30.0,
            size: Project.Sources.Size(w: 1280, h: 720),
            syncOffsetMs: 0,
            sha256: "def456",
            sizeBytes: 104857600
        ),
        audio: Project.Sources.AudioTracks(
            system: Project.Sources.AudioTracks.AudioTrack(
                path: "sources/system_audio.m4a",
                syncOffsetMs: 0,
                sha256: "ghi789",
                sizeBytes: 10485760
            ),
            mic: Project.Sources.AudioTracks.AudioTrack(
                path: "sources/mic_audio.m4a",
                syncOffsetMs: 0,
                sha256: "jkl012",
                sizeBytes: 10485760
            )
        ),
        telemetry: nil
    )

    let canvas = Project.Canvas(
        format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
        background: Project.Canvas.Background(type: "solid", value: "#000000"),
        layout: Project.Canvas.Layout(type: "pip", camera: nil)
    )

    return Project(
        schemaVersion: 1,
        projectId: UUID(),
        name: "Sample Project",
        tags: ["demo", "tutorial"],
        createdAt: Date(),
        updatedAt: Date(),
        sources: sources,
        timeline: timeline,
        canvas: canvas,
        overlays: [],
        captions: nil
    )
}
