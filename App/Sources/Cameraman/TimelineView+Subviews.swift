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
    let onSelectSegment: (Project.Timeline.Segment) -> Void
    let onTrimDragChanged: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void
    let onTrimDragEnded: (Project.Timeline.Segment, TimelineTrimEdge, TimelineScalar) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            HStack(spacing: 4) {
                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "eye.slash" : "eye")
                        .font(.caption2)
                        .foregroundStyle(isMuted ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16)

                Text(track.label)
                    .font(.caption)
                    .foregroundStyle(isMuted ? .tertiary : .secondary)
            }
            .frame(width: layout.labelWidth - 12, alignment: .leading)
            .padding(.leading, 6)

            ForEach(track.segments) { segment in
                let isSelected = segment.id == selectedSegmentId
                let width = layout.segmentWidth(for: segment.timelineDuration)
                let xPosition = layout.xPosition(for: segment.timelineIn)

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
                        if showWaveforms, let samples = waveformSamples, (track.kind == .systemAudio || track.kind == .micAudio) {
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isInteractive else { return }
                        onSelectSegment(segment)
                    }
                    .opacity(isMuted ? 0.3 : 1.0)
                    .offset(x: xPosition)
            }
        }
        .frame(height: height)
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
        let sortedTimes = thumbnails.keys.sorted()
        guard let closestTime = sortedTimes.min(by: { abs($0 - time) < abs($1 - time) }) else {
            return nil
        }

        // Only return if within 1 second
        if abs(closestTime - time) <= 1.0 {
            return thumbnails[closestTime]
        }

        return nil
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
        let effectiveHeight = max(2, height - (waveformPadding * 2))

        // Map waveform samples to segment time range
        let segmentSamples = samplesForSegment()

        GeometryReader { geometry in
            Path { path in
                guard !segmentSamples.isEmpty else { return }

                let sampleWidth = segmentWidth / CGFloat(segmentSamples.count)
                let centerY = effectiveHeight / 2

                for (index, sample) in segmentSamples.enumerated() {
                    let x = CGFloat(index) * sampleWidth

                    // Scale sample to height (samples are normalized -1.0 to 1.0)
                    let amplitude = CGFloat(abs(sample)) * centerY
                    let yStart = centerY - amplitude
                    let yEnd = centerY + amplitude

                    path.move(to: CGPoint(x: x, y: yStart))
                    path.addLine(to: CGPoint(x: x, y: yEnd))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
        }
        .frame(width: segmentWidth, height: height)
        .padding(.vertical, waveformPadding)
    }

    /// Extract waveform samples for this segment's time range
    private func samplesForSegment() -> [Float] {
        guard !waveformSamples.isEmpty else { return [] }

        let totalDuration = layout.duration
        let sampleCount = waveformSamples.count

        // Calculate sample range for this segment
        let startRatio = segment.timelineIn / totalDuration
        let endRatio = segment.timelineOut / totalDuration

        let startIndex = max(0, Int(startRatio * Double(sampleCount)))
        let endIndex = min(sampleCount, Int(endRatio * Double(sampleCount)))

        guard endIndex > startIndex else { return [] }

        return Array(waveformSamples[startIndex..<endIndex])
    }
}
