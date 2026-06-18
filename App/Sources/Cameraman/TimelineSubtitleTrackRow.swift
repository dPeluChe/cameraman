//
//  TimelineSubtitleTrackRow.swift
//  App
//
//  Timeline lane that renders subtitle cues as chips showing their text.
//  Tapping a cue seeks the playhead to its start; editing happens in the
//  Subtitles panel. Kept separate from the overlay row to avoid the overlay
//  popover (which edits `project.overlays`, not subtitles).
//

import SwiftUI
import EngineKit

struct TimelineSubtitleTrackRow: View {
    let cues: [Project.Overlay]
    let layout: TimelineLayout
    let height: TimelineScalar
    var onSeek: ((TimeInterval) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.labelWidth)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                ForEach(cues) { cue in
                    let duration = cue.end - cue.start
                    let width = layout.segmentWidth(for: duration)
                    let xPosition = layout.xPosition(for: cue.start) - layout.labelWidth

                    Text(cue.style.text ?? "")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                        .frame(width: max(width, 30), height: height - 10, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.indigo.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .offset(x: xPosition)
                        .highPriorityGesture(
                            TapGesture().onEnded { onSeek?(cue.start) }
                        )
                }
            }
            .frame(height: height)
        }
    }
}
