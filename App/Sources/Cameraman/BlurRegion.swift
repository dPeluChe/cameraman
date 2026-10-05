//
//  BlurRegion.swift
//  App
//
//  A `gaussianBlur` clip effect that has a region (x, y, w, h as fractions of the frame,
//  top-left origin). Shared by the Blur panel, the preview canvas and the timeline row.
//

import SwiftUI
import EngineKit

struct BlurRegion: Identifiable {
    let trackId: UUID
    let clip: Project.TimelineClip
    let adjustment: Project.Adjustment

    var id: String { "\(clip.id)/\(adjustment.id)" }
    var absoluteStart: TimeInterval { clip.timelineIn + (adjustment.start ?? 0) }
    var absoluteEnd: TimeInterval { clip.timelineIn + (adjustment.end ?? clip.duration) }

    /// Smallest region side, and so the furthest an origin can sit: at x = 1 there is no room left
    /// for a width, which validation rejects.
    static let minSide = 0.02

    var rect: CGRect {
        let p = adjustment.parameters
        return CGRect(x: p["x"] ?? 0, y: p["y"] ?? 0, width: p["w"] ?? 0.4, height: p["h"] ?? 0.1)
    }

    static func hasRegion(_ p: [String: Double]) -> Bool {
        ["x", "y", "w", "h"].allSatisfy { p[$0] != nil }
    }

    /// The effect with a new frame rect, clamped inside the frame (validation rejects x + w or y + h past 1).
    func moved(to rect: CGRect) -> Project.Adjustment {
        var p = adjustment.parameters
        let w = max(Self.minSide, min(rect.width, 1))
        let h = max(Self.minSide, min(rect.height, 1))
        p["w"] = w
        p["h"] = h
        p["x"] = max(0, min(rect.minX, 1 - w))
        p["y"] = max(0, min(rect.minY, 1 - h))
        return withParameters(p, start: adjustment.start, end: adjustment.end)
    }

    /// The effect shifted in time, keeping its length and staying inside its clip.
    func shifted(by delta: TimeInterval) -> Project.Adjustment {
        let length = (adjustment.end ?? clip.duration) - (adjustment.start ?? 0)
        let start = max(0, min((adjustment.start ?? 0) + delta, clip.duration - length))
        return withParameters(adjustment.parameters, start: start, end: start + length)
    }

    func withParameters(_ parameters: [String: Double], start: TimeInterval?, end: TimeInterval?) -> Project.Adjustment {
        Project.Adjustment(
            id: adjustment.id, kind: adjustment.kind, target: adjustment.target,
            parameters: parameters, enabled: adjustment.enabled, start: start, end: end
        )
    }
}

extension Project {
    var blurRegions: [BlurRegion] {
        timeline.tracks.flatMap { track in
            track.clips.flatMap { clip in
                (clip.adjustments ?? [])
                    .filter { $0.kind == .gaussianBlur && BlurRegion.hasRegion($0.parameters) }
                    .map { BlurRegion(trackId: track.id, clip: clip, adjustment: $0) }
            }
        }.sorted { $0.absoluteStart < $1.absoluteStart }
    }
}

/// Draggable frame for the selected blur region, drawn over the preview. Drag the body to move it,
/// the corner dot to resize. The edit is committed when the gesture ends.
struct BlurRegionCanvasEditor: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel

    @State private var gestureStart: CGRect?
    @State private var draft: CGRect?

    private var region: BlurRegion? {
        guard let id = editor.selectedBlurRegionId else { return nil }
        let t = playerViewModel.currentTime
        return editor.project.blurRegions.first { $0.id == id && t >= $0.absoluteStart && t <= $0.absoluteEnd }
    }

    var body: some View {
        GeometryReader { geo in
            if let region {
                let rect = draft ?? region.rect
                let frame = CGRect(x: rect.minX * geo.size.width, y: rect.minY * geo.size.height,
                                   width: rect.width * geo.size.width, height: rect.height * geo.size.height)
                ZStack(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                let start = gestureStart ?? region.rect
                                gestureStart = start
                                draft = CGRect(x: start.minX + drag.translation.width / geo.size.width,
                                               y: start.minY + drag.translation.height / geo.size.height,
                                               width: start.width, height: start.height)
                            }
                            .onEnded { _ in commit(region) })

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 7, y: 7)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                let start = gestureStart ?? region.rect
                                gestureStart = start
                                draft = CGRect(x: start.minX, y: start.minY,
                                               width: min(start.width + drag.translation.width / geo.size.width, 1 - start.minX),
                                               height: min(start.height + drag.translation.height / geo.size.height, 1 - start.minY))
                            }
                            .onEnded { _ in commit(region) })
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func commit(_ region: BlurRegion) {
        defer { gestureStart = nil }
        guard let rect = draft else { return }
        let updated = region.moved(to: rect)
        Task {
            _ = await editor.updateAdjustment(updated, inClipId: region.clip.id, trackId: region.trackId)
            draft = nil
        }
    }
}

/// Timeline lane for blur regions: one chip per region. Tap to select (and jump to it), drag to move in time.
struct TimelineBlurTrackRow: View {
    @ObservedObject var editor: ProjectEditor
    let regions: [BlurRegion]
    let layout: TimelineLayout
    let height: TimelineScalar
    let onSeek: (TimeInterval) -> Void

    @State private var dragOffset: [String: TimelineScalar] = [:]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.labelWidth)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                ForEach(regions) { region in
                    let isSelected = region.id == editor.selectedBlurRegionId
                    let width = layout.segmentWidth(for: region.absoluteEnd - region.absoluteStart)
                    HStack(spacing: 2) {
                        Image(systemName: "drop.halffull").font(.system(size: 8))
                        Text("Blur").font(.system(size: 8)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(width: max(width, 30), height: height - 10)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.purple.opacity(isSelected ? 1.0 : 0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.9 : 0.3), lineWidth: isSelected ? 2 : 1))
                    .offset(x: layout.xPosition(for: region.absoluteStart) - layout.labelWidth + (dragOffset[region.id] ?? 0))
                    // highPriority so the chip wins over the timeline's seek gesture
                    .highPriorityGesture(TapGesture().onEnded {
                        editor.selectedBlurRegionId = region.id
                        onSeek(region.absoluteStart)
                    })
                    .highPriorityGesture(DragGesture(minimumDistance: 4)
                        .onChanged { dragOffset[region.id] = $0.translation.width }
                        .onEnded { value in
                            dragOffset.removeValue(forKey: region.id)
                            let updated = region.shifted(by: TimeInterval(value.translation.width / layout.pixelsPerSecond))
                            editor.selectedBlurRegionId = region.id
                            Task { _ = await editor.updateAdjustment(updated, inClipId: region.clip.id, trackId: region.trackId) }
                        })
                    .help("Click to select, drag to move in time")
                }
            }
        }
    }
}
