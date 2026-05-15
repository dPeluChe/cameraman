//
//  TimelineView+MediaMarkers.swift
//  App
//
//  Waveform, thumbnail, zoom marker, and overlay track row views.
//  Extracted from TimelineView+Subviews.swift.
//

import SwiftUI
import EngineKit

// MARK: - Timeline Waveform Strip

struct TimelineWaveformStrip: View {
    let segment: Project.Timeline.Segment
    let layout: TimelineLayout
    let waveformSamples: [Float]
    let height: TimelineScalar
    let color: Color

    private let waveformPadding: TimelineScalar = 2

    var body: some View {
        let segmentWidth = layout.segmentWidth(for: segment.timelineDuration)
        let samples = waveformSamples
        let segRange = sampleRange()

        Canvas { context, size in
            guard segRange.count > 0 else { return }
            let effectiveHeight = max(2, size.height - (waveformPadding * 2))
            let sampleWidth = size.width / CGFloat(segRange.count)
            let centerY = effectiveHeight / 2

            var path = Path()
            for (i, sample) in samples[segRange].enumerated() {
                let x = CGFloat(i) * sampleWidth
                let amplitude = CGFloat(abs(sample)) * centerY
                path.move(to: CGPoint(x: x, y: centerY - amplitude))
                path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
        }
        .frame(width: segmentWidth, height: height)
        .padding(.vertical, waveformPadding)
    }

    private func sampleRange() -> Range<Int> {
        guard !waveformSamples.isEmpty, layout.duration > 0 else { return 0..<0 }
        let count = waveformSamples.count
        let start = max(0, Int((segment.timelineIn / layout.duration) * Double(count)))
        let end = min(count, Int((segment.timelineOut / layout.duration) * Double(count)))
        return start < end ? start..<end : 0..<0
    }
}

// MARK: - Zoom Suggestion Marker

struct ZoomSuggestionMarker: View {
    let suggestion: ZoomSuggestion
    let xPosition: TimelineScalar
    let height: TimelineScalar
    let isDismissed: Bool
    let onToggle: () -> Void

    private var markerColor: Color { isDismissed ? .gray : .yellow }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: suggestion.source == .dwell ? "eye.circle.fill" : "cursorarrow.click.2")
                .font(.system(size: 10))
                .foregroundStyle(markerColor)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .onTapGesture { onToggle() }

            Rectangle()
                .fill(markerColor.opacity(isDismissed ? 0.2 : 0.5))
                .frame(width: 1, height: max(0, height - 14))
        }
        .offset(x: xPosition - 7)
        .opacity(isDismissed ? 0.5 : 1.0)
        .help(String(format: "%@ zoom at %.1fs (%.1fx)%@",
                      suggestion.source == .dwell ? "Dwell" : "Click",
                      suggestion.timelineTime,
                      suggestion.zoomLevel,
                       isDismissed ? " (dismissed)" : " — click to dismiss"))
    }
}

// MARK: - Timeline Overlay Track Row

struct TimelineOverlayTrackRow: View {
    @ObservedObject var editor: ProjectEditor
    let overlays: [Project.Overlay]
    let layout: TimelineLayout
    let height: TimelineScalar
    @Binding var selectedOverlayId: UUID?
    let onOverlayDragged: (UUID, TimeInterval) -> Void
    var onPopoverOpened: ((TimeInterval) -> Void)? = nil
    var rowLabel: String = "Overlays"

    @State private var overlayDragOffset: [UUID: TimelineScalar] = [:]
    @State private var popoverOverlayId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Label column — matches other track rows for visual alignment
            Text(rowLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 6)
                .frame(width: layout.labelWidth, alignment: .leading)

            // Content ZStack — xPosition uses layout.xPosition - labelWidth (same as other tracks)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

            ForEach(overlays) { overlay in
                let duration = overlay.end - overlay.start
                let width = layout.segmentWidth(for: duration)
                let xPosition = layout.xPosition(for: overlay.start) - layout.labelWidth
                let isSelected = overlay.id == selectedOverlayId

                HStack(spacing: 2) {
                    Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(OverlayDisplayInfo.label(for: overlay.type))
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(width: max(width, 30), height: height - 10)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.cyan.opacity(isSelected ? 1.0 : 0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1)
                )
                .offset(x: xPosition + (overlayDragOffset[overlay.id] ?? 0))
                .popover(isPresented: Binding(
                    get: { popoverOverlayId == overlay.id },
                    set: { if !$0 { popoverOverlayId = nil } }
                ), arrowEdge: .top) {
                    OverlayPopoverContent(editor: editor, overlayId: overlay.id)
                }
                // highPriority so the chip tap wins over the timeline's seek DragGesture(minimumDistance:0)
                .highPriorityGesture(
                    TapGesture()
                        .onEnded {
                            selectedOverlayId = overlay.id
                            popoverOverlayId = overlay.id
                            let fadeIn = overlay.animation?.fadeInDuration ?? 0
                            let dur = overlay.end - overlay.start
                            let seekTarget = overlay.start + min(fadeIn + 0.05, dur * 0.3)
                            onPopoverOpened?(seekTarget)
                        }
                )
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            overlayDragOffset[overlay.id] = value.translation.width
                        }
                        .onEnded { value in
                            let deltaX = value.translation.width
                            overlayDragOffset.removeValue(forKey: overlay.id)
                            let deltaTime = TimeInterval(deltaX / layout.pixelsPerSecond)
                            onOverlayDragged(overlay.id, deltaTime)
                        }
                )
                .help("Click to select and edit properties")
            }
            } // end content ZStack
        } // end HStack
    }

}
