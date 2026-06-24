//
//  TimelineSubtitleTrackRow.swift
//  App
//
//  Timeline lane that renders subtitle cues as chips showing their text.
//  Tapping a cue selects it and seeks the playhead; the selected cue gets
//  leading/trailing trim handles (adjust start/end) and can be dragged to move.
//  Kept separate from the overlay row to avoid the overlay popover (which edits
//  `project.overlays`, not subtitles).
//

import SwiftUI
import EngineKit

struct TimelineSubtitleTrackRow: View {
    let cues: [Project.Overlay]
    let layout: TimelineLayout
    let height: TimelineScalar
    @Binding var selectedOverlayId: UUID?
    var onSeek: ((TimeInterval) -> Void)? = nil
    /// Move a cue by a time delta (keeps its duration).
    var onMove: ((UUID, TimeInterval) -> Void)? = nil
    /// Trim a cue's leading/trailing edge by a time delta.
    var onTrim: ((UUID, TimelineTrimEdge, TimeInterval) -> Void)? = nil

    @State private var dragOffset: [UUID: TimelineScalar] = [:]
    @State private var leadingTrim: [UUID: TimelineScalar] = [:]
    @State private var trailingTrim: [UUID: TimelineScalar] = [:]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.labelWidth, height: height)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                ForEach(cues) { cue in
                    cueChip(cue)
                }
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func cueChip(_ cue: Project.Overlay) -> some View {
        let isSelected = cue.id == selectedOverlayId
        let baseWidth = layout.segmentWidth(for: cue.end - cue.start)
        let lead = leadingTrim[cue.id] ?? 0
        let trail = trailingTrim[cue.id] ?? 0
        // Leading trim moves the left edge and shrinks width; trailing grows width.
        let width = max(20, baseWidth - lead + trail)
        let xPosition = layout.xPosition(for: cue.start) - layout.labelWidth
            + (dragOffset[cue.id] ?? 0) + lead

        Text(cue.style.text ?? "")
            .font(.system(size: 8))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .frame(width: width, height: height - 10, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.indigo.opacity(isSelected ? 1.0 : 0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    TimelineTrimHandle(
                        edge: .leading,
                        height: height - 10,
                        onDragChanged: { leadingTrim[cue.id] = $0 },
                        onDragEnded: { delta in
                            leadingTrim[cue.id] = nil
                            onTrim?(cue.id, .leading, TimeInterval(delta / layout.pixelsPerSecond))
                        }
                    )
                }
            }
            .overlay(alignment: .trailing) {
                if isSelected {
                    TimelineTrimHandle(
                        edge: .trailing,
                        height: height - 10,
                        onDragChanged: { trailingTrim[cue.id] = $0 },
                        onDragEnded: { delta in
                            trailingTrim[cue.id] = nil
                            onTrim?(cue.id, .trailing, TimeInterval(delta / layout.pixelsPerSecond))
                        }
                    )
                }
            }
            .offset(x: xPosition)
            .highPriorityGesture(
                TapGesture().onEnded {
                    selectedOverlayId = cue.id
                    onSeek?(cue.start)
                }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in dragOffset[cue.id] = value.translation.width }
                    .onEnded { value in
                        dragOffset[cue.id] = nil
                        onMove?(cue.id, TimeInterval(value.translation.width / layout.pixelsPerSecond))
                    }
            )
    }
}
