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
    @State private var lastError: String?

    private typealias Region = BlurRegion

    private var regions: [Region] { editor.project.blurRegions }

    private static let minSide = BlurRegion.minSide
    private static var maxOrigin: Double { 1 - minSide }

    static func hasRegion(_ p: [String: Double]) -> Bool { BlurRegion.hasRegion(p) }

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

            if let lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                    .fontWeight(editor.selectedBlurRegionId == region.id ? .bold : .regular)
                if editor.selectedBlurRegionId == region.id {
                    Text("on canvas").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor.selectedBlurRegionId = region.id
                    selectTime(region.absoluteStart)
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.plain)
                .help("Select it and jump to its start, then drag it on the preview")
                Button {
                    if editor.selectedBlurRegionId == region.id { editor.selectedBlurRegionId = nil }
                    run { await editor.removeAdjustment(region.adjustment.id, fromClipId: region.clip.id, inTrackId: region.trackId) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            slider("X", region, key: "x", value: p["x"] ?? 0, range: 0...Self.maxOrigin)
            slider("Y", region, key: "y", value: p["y"] ?? 0, range: 0...Self.maxOrigin)
            slider("Width", region, key: "w", value: p["w"] ?? 0.4, range: Self.minSide...1)
            slider("Height", region, key: "h", value: p["h"] ?? 0.1, range: Self.minSide...1)
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
        let duration = target.clip.duration
        let start = min(max(0, playerViewModel.currentTime - target.clip.timelineIn), duration - 0.1)
        let end = min(duration, start + 5)
        guard start >= 0, start < end else { return }
        // A wide, short band near the middle: the shape of a key or an email, easy to move from there.
        let adjustment = Project.Adjustment(
            kind: .gaussianBlur, target: .frame,
            parameters: ["radius": 24, "x": 0.3, "y": 0.44, "w": 0.4, "h": 0.12],
            start: start, end: end
        )
        editor.selectedBlurRegionId = "\(target.clip.id)/\(adjustment.id)"
        run { await editor.addAdjustment(adjustment, toClipId: target.clip.id, inTrackId: target.trackId) }
    }

    private func commit(_ region: Region, key: String, value: Double) {
        var params = region.adjustment.parameters
        params[key] = value
        // Keep the region inside the frame (validation rejects x + w or y + h past 1). The sliders
        // follow the stored value, so a clamp here shows up on them.
        if let x = params["x"], let w = params["w"] { params["w"] = max(Self.minSide, min(w, 1 - x)) }
        if let y = params["y"], let h = params["h"] { params["h"] = max(Self.minSide, min(h, 1 - y)) }
        update(region, parameters: params, start: region.adjustment.start, end: region.adjustment.end)
    }

    private func timeBinding(_ region: Region, isStart: Bool, clipDuration: TimeInterval) -> Binding<Double> {
        Binding(
            get: { (isStart ? region.adjustment.start : region.adjustment.end) ?? (isStart ? 0 : clipDuration) },
            set: { newValue in
                // Times live in the clip's timeline seconds and are checked against its current length,
                // which shrinks if the clip is trimmed or sped up after the region was made.
                var start = min(region.adjustment.start ?? 0, clipDuration - 0.1)
                var end = min(region.adjustment.end ?? clipDuration, clipDuration)
                if isStart { start = min(newValue, end - 0.1) } else { end = min(max(newValue, start + 0.1), clipDuration) }
                update(region, parameters: region.adjustment.parameters, start: max(0, start), end: end)
            }
        )
    }

    private func update(_ region: Region, parameters: [String: Double], start: TimeInterval?, end: TimeInterval?) {
        let updated = Project.Adjustment(
            id: region.adjustment.id, kind: region.adjustment.kind, target: region.adjustment.target,
            parameters: parameters, enabled: region.adjustment.enabled, start: start, end: end
        )
        run { await editor.updateAdjustment(updated, inClipId: region.clip.id, trackId: region.trackId) }
    }

    /// A rejected edit used to vanish silently; show why.
    private func run(_ operation: @escaping () async -> EditorResult) {
        Task {
            if case .failure(let error) = await operation() {
                lastError = error.localizedDescription
                LogWarning(.editor, "[BLUR] edit rejected: \(error.localizedDescription)")
            } else {
                lastError = nil
            }
        }
    }

    private func selectTime(_ seconds: TimeInterval) { playerViewModel.seek(to: seconds) }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        return String(format: "%d:%04.1f", minutes, clamped - Double(minutes * 60))
    }
}
