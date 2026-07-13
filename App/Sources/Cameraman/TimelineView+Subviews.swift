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
    let onSelectMediaItem: (UUID?) -> Void
    let onToggleMute: () -> Void
    // Imported-video clip interactions (only used by .videoClip rows)
    var selectedVideoClipId: String?
    var onVideoClipMoved: (Project.TimelineClip, TimelineScalar) -> Void = { _, _ in }
    var onVideoClipTrimmed: (Project.TimelineClip, TimelineTrimEdge, TimelineScalar) -> Void = { _, _, _ in }
    var onSelectVideoClip: (Project.TimelineClip) -> Void = { _ in }
    var onVideoClipAction: (Project.TimelineClip, VideoClipAction) -> Void = { _, _ in }
    /// Adjusts a drag delta to magnetic snap points; identity by default.
    var snapClipDeltaX: (Project.TimelineClip, TimelineScalar) -> TimelineScalar = { _, delta in delta }
    /// When false the label is replaced by a transparent spacer of the same
    /// width — used with the fixed label column that overlays the scroll view.
    var showsLabel: Bool = true

    @State private var mediaItemDragOffset: [UUID: TimelineScalar] = [:]
    @State private var clipDragOffset: [String: TimelineScalar] = [:]
    @State private var clipTrimOffset: [String: (edge: TimelineTrimEdge, delta: TimelineScalar)] = [:]

    var body: some View {
        HStack(spacing: 0) {
            // Track label (or a same-width spacer when the fixed column shows it)
            if showsLabel {
                TimelineTrackLabelView(
                    track: track,
                    isMuted: isMuted,
                    volumeBinding: volumeBinding,
                    onToggleMute: onToggleMute
                )
                .frame(width: layout.labelWidth, alignment: .leading)
                .padding(.leading, 6)
            } else {
                Color.clear
                    .frame(width: layout.labelWidth)
                    .padding(.leading, 6)
            }

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
                .onTapGesture {
                    onSelectMediaItem(item.id)
                }
                .highPriorityGesture(
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

            // Render imported-video clips (new-model .video tracks):
            // body drag = move, edge drags = trim, click = select/position
            ForEach(track.timelineClips) { clip in
                let trim = clipTrimOffset[clip.id]
                let leadingDelta: TimelineScalar = trim?.edge == .leading ? (trim?.delta ?? 0) : 0
                let trailingDelta: TimelineScalar = trim?.edge == .trailing ? (trim?.delta ?? 0) : 0
                let baseWidth = layout.segmentWidth(for: clip.duration)
                let width = max(10, baseWidth - leadingDelta + trailingDelta)
                let xPosition = layout.xPosition(for: clip.timelineIn) - layout.labelWidth
                    + leadingDelta + (clipDragOffset[clip.id] ?? 0)
                let isSelected = clip.id == selectedVideoClipId

                HStack(spacing: 2) {
                    Image(systemName: clipIconName(clip))
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(clipDisplayName(clip))
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
                        .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                )
                .overlay(isSelected ? videoClipTrimHandles(for: clip) : nil)
                .opacity(isMuted ? 0.3 : 1.0)
                .offset(x: xPosition)
                .onTapGesture {
                    onSelectVideoClip(clip)
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            clipDragOffset[clip.id] = snapClipDeltaX(clip, value.translation.width)
                        }
                        .onEnded { value in
                            clipDragOffset.removeValue(forKey: clip.id)
                            onVideoClipMoved(clip, snapClipDeltaX(clip, value.translation.width))
                        }
                )
                .contextMenu {
                    Button("Split at Playhead") { onVideoClipAction(clip, .splitAtPlayhead) }
                    Button("Jump to Clip End") { onVideoClipAction(clip, .jumpToEnd) }
                    Button("Place After Track Above") { onVideoClipAction(clip, .placeAfterPreviousTrack) }
                    Button("Place at Start") { onVideoClipAction(clip, .placeAtStart) }
                    Divider()
                    Button("Move Row Up") { onVideoClipAction(clip, .moveRowUp) }
                    Button("Move Row Down") { onVideoClipAction(clip, .moveRowDown) }
                    Divider()
                    Button("Remove Clip", role: .destructive) { onVideoClipAction(clip, .remove) }
                }
                .help("\(clipDisplayName(clip)) — \(String(format: "%.1fs", clip.duration)). Drag to move, edges to trim, click to position.")
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

    /// Invisible 8pt drag zones on each edge of a video clip chip for trimming.
    @ViewBuilder
    private func videoClipTrimHandles(for clip: Project.TimelineClip) -> some View {
        HStack(spacing: 0) {
            trimHandle(for: clip, edge: .leading)
            Spacer(minLength: 0)
            trimHandle(for: clip, edge: .trailing)
        }
    }

    private func trimHandle(for clip: Project.TimelineClip, edge: TimelineTrimEdge) -> some View {
        // Visible affordance: handles only exist on the SELECTED chip (body drags
        // on short clips kept landing on invisible 8pt handles and trimming when
        // the user meant to move).
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(clipTrimOffset[clip.id]?.edge == edge ? 0.9 : 0.55))
            .frame(width: 5)
            .padding(.vertical, 4)
            .padding(.horizontal, 1.5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        clipTrimOffset[clip.id] = (edge: edge, delta: value.translation.width)
                    }
                    .onEnded { value in
                        clipTrimOffset.removeValue(forKey: clip.id)
                        onVideoClipTrimmed(clip, edge, value.translation.width)
                    }
            )
    }

    /// File name for an imported video/audio clip chip (e.g. "assets/broll.mp4" -> "broll.mp4")
    private func clipDisplayName(_ clip: Project.TimelineClip) -> String {
        switch clip.content {
        case .video(let ref): return (ref.path as NSString).lastPathComponent
        case .audio(let ref): return (ref.path as NSString).lastPathComponent
        case .image(let ref): return (ref.path as NSString).lastPathComponent
        case .color: return "Color"
        case .recording: return "Recording"
        }
    }

    private func clipIconName(_ clip: Project.TimelineClip) -> String {
        switch clip.content {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .color: return "rectangle.fill"
        case .recording: return "rectangle.dashed"
        }
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
