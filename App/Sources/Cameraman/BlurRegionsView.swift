//
//  BlurRegionsView.swift
//  App
//
//  "Blur" tool: hide part of the screen (an API key, an email, a card number) for a stretch of
//  the video. Each region is a `gaussianBlur` adjustment with x, y, w, h (fractions of the frame,
//  top-left origin) attached to the recording clip it covers, limited in time with start/end.
//

import SwiftUI
import EngineKit

struct BlurRegionsView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel

    private struct Region: Identifiable {
        let trackId: UUID
        let clip: Project.TimelineClip
        let adjustment: Project.Adjustment
        var id: UUID { adjustment.id }
        var absoluteStart: TimeInterval { clip.timelineIn + (adjustment.start ?? 0) }
        var absoluteEnd: TimeInterval { clip.timelineIn + (adjustment.end ?? clip.duration) }
    }

    /// Clip-relative start/end are shown on the timeline, so a region reads the same as the playhead.
    private var regions: [Region] {
        editor.project.timeline.tracks.flatMap { track in
            track.clips.flatMap { clip in
                (clip.adjustments ?? [])
                    .filter { $0.kind == .gaussianBlur && Self.hasRegion($0.parameters) }
                    .map { Region(trackId: track.id, clip: clip, adjustment: $0) }
            }
        }.sorted { $0.absoluteStart < $1.absoluteStart }
    }

    static func hasRegion(_ p: [String: Double]) -> Bool {
        ["x", "y", "w", "h"].allSatisfy { p[$0] != nil }
    }

    /// The recording clip under the playhead, where a new region attaches.
    private var clipAtPlayhead: (trackId: UUID, clip: Project.TimelineClip)? {
        let t = playerViewModel.currentTime
        for track in editor.project.timeline.tracks where track.type == .primary {
            if let clip = track.clips.first(where: { $0.timelineIn <= t && t < $0.timelineOut }) {
                return (track.id, clip)
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blur a part of the screen for a stretch of the video. Move the playhead, add a region, then size it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                addRegion()
            } label: {
                Label("Add blur at playhead", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(clipAtPlayhead == nil)
            .help(clipAtPlayhead == nil ? "Move the playhead onto the recording" : "Blur 5 seconds from the playhead")

            if regions.isEmpty {
                Text("No blur regions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(regions) { region in
                    regionRow(region)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    @ViewBuilder
    private func regionRow(_ region: Region) -> some View {
        let p = region.adjustment.parameters
        let clipDuration = region.clip.duration
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Self.timeLabel(region.absoluteStart)) - \(Self.timeLabel(region.absoluteEnd))")
                    .font(.caption.monospacedDigit())
                Spacer()
                Button {
                    selectTime(region.absoluteStart)
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.plain)
                .help("Jump to the start of this blur")
                Button {
                    Task { _ = await editor.removeAdjustment(region.adjustment.id, fromClipId: region.clip.id, inTrackId: region.trackId) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            slider("X", region, key: "x", value: p["x"] ?? 0, range: 0...1)
            slider("Y", region, key: "y", value: p["y"] ?? 0, range: 0...1)
            slider("Width", region, key: "w", value: p["w"] ?? 0.4, range: 0.02...1)
            slider("Height", region, key: "h", value: p["h"] ?? 0.1, range: 0.02...1)
            slider("Strength", region, key: "radius", value: p["radius"] ?? 24, range: 4...60)
            HStack(spacing: 8) {
                Text("Time").font(.caption2).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Stepper("Start \(Self.timeLabel(region.absoluteStart))", value: timeBinding(region, isStart: true, clipDuration: clipDuration),
                        in: 0...max(0, clipDuration - 0.1), step: 0.5)
                    .font(.caption2.monospacedDigit())
                Stepper("End \(Self.timeLabel(region.absoluteEnd))", value: timeBinding(region, isStart: false, clipDuration: clipDuration),
                        in: 0.1...max(0.1, clipDuration), step: 0.5)
                    .font(.caption2.monospacedDigit())
            }
        }
    }

    private func slider(_ title: String, _ region: Region, key: String, value: Double, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption2).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            AdjustmentSlider(value: value, range: range) { commit(region, key: key, value: $0) }
        }
    }

    // MARK: - Editing

    private func addRegion() {
        guard let target = clipAtPlayhead else { return }
        let start = max(0, playerViewModel.currentTime - target.clip.timelineIn)
        let end = min(target.clip.duration, start + 5)
        // A wide, short band near the middle: the shape of a key or an email, easy to move from there.
        let adjustment = Project.Adjustment(
            kind: .gaussianBlur, target: .frame,
            parameters: ["radius": 24, "x": 0.3, "y": 0.44, "w": 0.4, "h": 0.12],
            start: start, end: end
        )
        Task { _ = await editor.addAdjustment(adjustment, toClipId: target.clip.id, inTrackId: target.trackId) }
    }

    private func commit(_ region: Region, key: String, value: Double) {
        var params = region.adjustment.parameters
        params[key] = value
        // Keep the region inside the frame: validation rejects x + w or y + h past 1.
        if let x = params["x"], let w = params["w"] { params["w"] = min(w, 1 - x) }
        if let y = params["y"], let h = params["h"] { params["h"] = min(h, 1 - y) }
        let updated = Project.Adjustment(
            id: region.adjustment.id, kind: region.adjustment.kind, target: region.adjustment.target,
            parameters: params, enabled: region.adjustment.enabled,
            start: region.adjustment.start, end: region.adjustment.end
        )
        Task { _ = await editor.updateAdjustment(updated, inClipId: region.clip.id, trackId: region.trackId) }
    }

    private func timeBinding(_ region: Region, isStart: Bool, clipDuration: TimeInterval) -> Binding<Double> {
        Binding(
            get: { (isStart ? region.adjustment.start : region.adjustment.end) ?? (isStart ? 0 : clipDuration) },
            set: { newValue in
                var start = region.adjustment.start ?? 0
                var end = region.adjustment.end ?? clipDuration
                if isStart { start = min(newValue, end - 0.1) } else { end = max(newValue, start + 0.1) }
                let updated = Project.Adjustment(
                    id: region.adjustment.id, kind: region.adjustment.kind, target: region.adjustment.target,
                    parameters: region.adjustment.parameters, enabled: region.adjustment.enabled, start: start, end: end
                )
                Task { _ = await editor.updateAdjustment(updated, inClipId: region.clip.id, trackId: region.trackId) }
            }
        )
    }

    private func selectTime(_ seconds: TimeInterval) { playerViewModel.seek(to: seconds) }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
