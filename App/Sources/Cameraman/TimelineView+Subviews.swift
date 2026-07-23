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
            .fill(Color.primary.opacity(0.9))
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



// MARK: - Track Label

/// Eye/mute toggle + name + optional volume slider for one track row. Used both
/// inline (legacy) and by the fixed label column that overlays the scroll view.
struct TimelineTrackLabelView: View {
    let track: TimelineTrack
    let isMuted: Bool
    let volumeBinding: Binding<Float>?
    let onToggleMute: () -> Void

    var body: some View {
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
    }
}

// MARK: - Manual Zoom Keyframe Marker

struct ManualZoomKeyframeMarker: View {
    let keyframe: ZoomPlanGenerator.ZoomKeyframe
    let xPosition: TimelineScalar
    let height: TimelineScalar
    let pixelsPerSecond: TimelineScalar
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil
    var onDragChanged: ((TimeInterval) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onLiveUpdate: (() -> Void)? = nil
    var onContextMenuDelete: (() -> Void)? = nil

    @State private var dragStartTimestamp: TimeInterval = 0
    @State private var isDragging = false
    @State private var lastLiveUpdate: Date = .distantPast

    var body: some View {
        VStack(spacing: 1) {
            // Zoom level label above the dot
            if keyframe.zoomLevel > 1.01 {
                Text(String(format: "%.1fx", keyframe.zoomLevel))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? Color.yellow : Color.orange)
                    .allowsHitTesting(false)
            }
            Circle()
                .fill(isSelected ? Color.yellow : Color.orange)
                .frame(width: isSelected ? 12 : 10, height: isSelected ? 12 : 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: (isSelected ? Color.yellow : Color.orange).opacity(0.4), radius: 2)
            Rectangle()
                .fill((isSelected ? Color.yellow : Color.orange).opacity(0.5))
                .frame(width: 1.5, height: max(0, height - 22))
        }
        .offset(x: xPosition - 5)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            Button("Delete Keyframe", role: .destructive) {
                onContextMenuDelete?()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartTimestamp = keyframe.timestamp
                    }
                    let pps = max(pixelsPerSecond, 0.001)
                    let deltaSeconds = TimeInterval(value.translation.width) / TimeInterval(pps)
                    onDragChanged?(dragStartTimestamp + deltaSeconds)
                    // Throttle live preview to ~30fps
                    let now = Date()
                    if now.timeIntervalSince(lastLiveUpdate) > 0.033 {
                        lastLiveUpdate = now
                        onLiveUpdate?()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnded?()
                }
        )
        .help(String(format: "Manual zoom %.1fx at %.2fs", keyframe.zoomLevel, keyframe.timestamp))
    }
}

// MARK: - Zoom Curve Overlay

/// Mini graph showing zoom intensity over time. Draws a filled curve
/// proportional to zoom level across the timeline. Manual keyframes are
/// highlighted as orange dots; auto-zoom areas use a blue tint.
struct ZoomCurveOverlay: View {
    let keyframes: [ZoomPlanGenerator.ZoomKeyframe]
    let layout: TimelineLayout
    let height: TimelineScalar
    let maxZoomLevel: Double

    private let curveHeight: TimelineScalar = 24
    private let bottomPadding: TimelineScalar = 2

    var body: some View {
        if keyframes.isEmpty { EmptyView() } else {
            Canvas { context, size in
                let baseY = height - bottomPadding
                let topY = baseY - curveHeight
                let yRange = baseY - topY

                guard let firstKf = keyframes.first else { return }

                // Build path from keyframes
                var path = Path()
                let startX = layout.xPosition(for: firstKf.timestamp)
                let startZoom = firstKf.zoomLevel
                let startY = baseY - (CGFloat(startZoom / maxZoomLevel) * yRange)
                path.move(to: CGPoint(x: startX, y: baseY))
                path.addLine(to: CGPoint(x: startX, y: startY))

                for i in 1..<keyframes.count {
                    let kf = keyframes[i]
                    let x = layout.xPosition(for: kf.timestamp)
                    let y = baseY - (CGFloat(kf.zoomLevel / maxZoomLevel) * yRange)
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                // Close path to bottom
                if let lastKf = keyframes.last {
                    let lastX = layout.xPosition(for: lastKf.timestamp)
                    path.addLine(to: CGPoint(x: lastX, y: baseY))
                    path.closeSubpath()
                }

                // Fill gradient
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [
                        Color.orange.opacity(0.3),
                        Color.orange.opacity(0.05)
                    ]),
                    startPoint: CGPoint(x: 0, y: topY),
                    endPoint: CGPoint(x: 0, y: baseY)
                ))

                // Stroke the top curve
                var strokePath = Path()
                strokePath.move(to: CGPoint(x: startX, y: startY))
                for i in 1..<keyframes.count {
                    let kf = keyframes[i]
                    let x = layout.xPosition(for: kf.timestamp)
                    let y = baseY - (CGFloat(kf.zoomLevel / maxZoomLevel) * yRange)
                    strokePath.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(strokePath, with: .color(Color.orange.opacity(0.6)), lineWidth: 1.5)
            }
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
}
