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
