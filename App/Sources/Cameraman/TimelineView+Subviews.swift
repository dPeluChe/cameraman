//
//  TimelineView+Subviews.swift
//  App
//
//  Extracted from TimelineView.swift
//  Supporting subviews for timeline rendering
//

import SwiftUI
import EngineKit
import CoreGraphics

// MARK: - Timeline Track Row

struct TimelineTrackRow: View {
    let track: TimelineTrack
    let layout: TimelineLayout
    let height: TimelineScalar
    let selectedSegmentId: String?
    let isInteractive: Bool
    let isMuted: Bool
    let showThumbnails: Bool
    let thumbnails: [TimeInterval: NSImage]
    let showWaveforms: Bool
    let waveformSamples: [Float]?
    let volumeBinding: Binding<Float>?
    let onSelectSegment: (Project.Timeline.Segment) -> Void
    let onTrimDragChanged: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void
    let onTrimDragEnded: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void
    let onMediaItemDragged: (UUID, TimelineScalar) -> Void
    let onToggleMute: () -> Void

    @State private var mediaItemDragOffset: [UUID: TimelineScalar] = [:]

    var body: some View {
        HStack(spacing: 0) {
            // Track label with mute toggle and optional volume slider (fixed width, not in ZStack)
            HStack(spacing: 4) {
                Button(action: onToggleMute) {
                    Image(systemName: isMuted
                        ? (track.kind.isAudioTrack ? "speaker.slash" : "eye.slash")
                        : (track.kind.isAudioTrack ? "speaker.wave.2" : "eye"))
                        .font(.caption2)
                        .foregroundStyle(isMuted ? .tertiary : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(track.label)
                    .font(.caption)
                    .foregroundStyle(isMuted ? .tertiary : .secondary)
                    .lineLimit(1)

                if let binding = volumeBinding {
                    Slider(value: binding, in: 0...3)
                        .frame(width: 48)
                        .controlSize(.mini)
                        .opacity(isMuted ? 0.4 : 1.0)
                        .help(String(format: "Volume: %.1fx", binding.wrappedValue))
                }
            }
            .frame(width: layout.labelWidth, alignment: .leading)
            .padding(.leading, 6)

            // Track content (segments)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

            // Render media items (for additional audio / image tracks)
            ForEach(track.mediaItems) { item in
                let width = layout.segmentWidth(for: item.duration)
                let xPosition = layout.xPosition(for: item.timelineIn) - layout.labelWidth

                HStack(spacing: 2) {
                    Image(systemName: item.type == .audio ? "waveform" : "photo")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(item.name)
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
                .frame(width: width, height: height - 10)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(track.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .opacity(item.isMuted || isMuted ? 0.3 : 1.0)
                .offset(x: xPosition)
                .offset(x: mediaItemDragOffset[item.id] ?? 0)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            mediaItemDragOffset[item.id] = value.translation.width
                        }
                        .onEnded { value in
                            mediaItemDragOffset.removeValue(forKey: item.id)
                            onMediaItemDragged(item.id, value.translation.width)
                        }
                )
                .help("\(item.name) — \(String(format: "%.1fs", item.duration))")
            }

            ForEach(track.segments) { segment in
                let isSelected = segment.id == selectedSegmentId
                let width = layout.segmentWidth(for: segment.timelineDuration)
                let xPosition = layout.xPosition(for: segment.timelineIn) - layout.labelWidth

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(track.color.opacity(showThumbnails || showWaveforms ? 0.3 : 1.0))
                    .frame(width: width, height: height - 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay {
                        // Render thumbnails for screen track
                        if showThumbnails && !thumbnails.isEmpty && track.kind == .screen {
                            TimelineThumbnailStrip(
                                segment: segment,
                                layout: layout,
                                thumbnails: thumbnails,
                                height: height - 10
                            )
                        }

                        // Render waveforms for audio tracks
                        if showWaveforms, let samples = waveformSamples, track.kind.isAudioTrack {
                            TimelineWaveformStrip(
                                segment: segment,
                                layout: layout,
                                waveformSamples: samples,
                                height: height - 10,
                                color: track.color
                            )
                        }
                    }
                    .overlay(alignment: .leading) {
                        if isInteractive && isSelected {
                            TimelineTrimHandle(
                                edge: .leading,
                                height: height,
                                onDragChanged: { deltaX in
                                    onTrimDragChanged(segment, .leading, deltaX)
                                },
                                onDragEnded: { deltaX in
                                    onTrimDragEnded(segment, .leading, deltaX)
                                }
                            )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isInteractive && isSelected {
                            TimelineTrimHandle(
                                edge: .trailing,
                                height: height,
                                onDragChanged: { deltaX in
                                    onTrimDragChanged(segment, .trailing, deltaX)
                                },
                                onDragEnded: { deltaX in
                                    onTrimDragEnded(segment, .trailing, deltaX)
                                }
                            )
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if segment.speed != 1.0 {
                            Text(String(format: "%.1fx", segment.speed))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.8)))
                                .padding(2)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if segment.cameraPosition != nil {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                                .padding(2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isInteractive else { return }
                        onSelectSegment(segment)
                    }
                    .opacity(isMuted ? 0.3 : 1.0)
                    .offset(x: xPosition)
                }
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Timeline Playhead View

struct TimelinePlayheadView: View {
    let xPosition: TimelineScalar
    let height: TimelineScalar

    var body: some View {
        Rectangle()
            .fill(Color.red.opacity(0.9))
            .frame(width: 2, height: height)
            .offset(x: xPosition)
    }
}

// MARK: - Timeline Range Selection View

struct TimelineRangeSelectionView: View {
    let selection: RangeSelection
    let layout: TimelineLayout
    let height: TimelineScalar

    var body: some View {
        let startX = layout.xPosition(for: selection.startTime)
        let endX = layout.xPosition(for: selection.endTime)
        let width = max(2, endX - startX)

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .offset(x: startX)
    }
}

// MARK: - Timeline Trim Edge & Handle

enum TimelineTrimEdge {
    case leading
    case trailing
}

struct TimelineTrimHandle: View {
    let edge: TimelineTrimEdge
    let height: TimelineScalar
    let onDragChanged: (TimelineScalar) -> Void
    let onDragEnded: (TimelineScalar) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 6, height: height - 14)
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 0)
            .padding(edge == .leading ? .leading : .trailing, 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDragChanged(value.translation.width)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation.width)
                    }
            )
    }
}

// MARK: - Timeline Thumbnail Strip

/// Renders a strip of thumbnails within a timeline segment
struct TimelineThumbnailStrip: View {
    let segment: Project.Timeline.Segment
    let layout: TimelineLayout
    let thumbnails: [TimeInterval: NSImage]
    let height: TimelineScalar

    private let thumbnailSpacing: TimelineScalar = 4
    private let minThumbnailWidth: TimelineScalar = 30

    var body: some View {
        let segmentWidth = layout.segmentWidth(for: segment.timelineDuration)

        // Calculate how many thumbnails fit in the segment
        let thumbnailCount = max(1, Int(segmentWidth / (minThumbnailWidth + thumbnailSpacing)))
        let interval = segment.timelineDuration / Double(max(thumbnailCount - 1, 1))

        ZStack {
            ForEach(0..<thumbnailCount, id: \.self) { index in
                let time = segment.timelineIn + (Double(index) * interval)
                let relativeTime = time - segment.timelineIn
                let thumbnailX = (relativeTime / segment.timelineDuration) * segmentWidth

                if let thumbnail = findClosestThumbnail(for: time) {
                    GeometryReader { geometry in
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: minThumbnailWidth, height: height)
                            .clipped()
                            .opacity(0.7)
                            .offset(x: thumbnailX)
                    }
                }
            }
        }
        .frame(width: segmentWidth, height: height)
        .clipped()
    }

    private func findClosestThumbnail(for time: TimeInterval) -> NSImage? {
        guard !thumbnails.isEmpty else { return nil }
        // O(n) linear scan — cheaper than sorting keys every render
        var bestTime: TimeInterval?
        var bestDist = Double.greatestFiniteMagnitude
        for key in thumbnails.keys {
            let dist = abs(key - time)
            if dist < bestDist { bestDist = dist; bestTime = key }
        }
        guard let closest = bestTime, bestDist <= 1.0 else { return nil }
        return thumbnails[closest]
    }
}

// MARK: - Timeline Waveform Strip

/// Renders an audio waveform visualization within a timeline segment
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
