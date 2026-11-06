//
//  ClipPlacementLayer.swift
//  App
//
//  Drag the timeline-selected clip on the preview. The handle resizes it, keeping its shape.
//

import SwiftUI
import EngineKit

struct ClipPlacementLayer: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    let selected: SelectedVideoClip

    @State private var draft: Project.MediaPosition?

    private static let fullCanvas = Project.MediaPosition(x: 0, y: 0, w: 1, h: 1)

    /// Live clip, only while the playhead is on it: otherwise there is nothing to place.
    private var clip: Project.TimelineClip? {
        let track = editor.project.timeline.tracks.first { $0.id == selected.trackId }
        guard let clip = track?.clips.first(where: { $0.id == selected.clip.id }), clip.isVisual else { return nil }
        let time = playerViewModel.currentTime
        return time >= clip.timelineIn && time <= clip.timelineOut ? clip : nil
    }

    var body: some View {
        GeometryReader { geometry in
            if let clip {
                placement(of: clip, position: clip.position ?? Self.fullCanvas, in: geometry.size)
            }
        }
        .clipped()
    }

    private func placement(of clip: Project.TimelineClip, position: Project.MediaPosition, in size: CGSize) -> some View {
        let shown = draft ?? position
        let rect = CGRect(x: shown.x * size.width, y: shown.y * size.height,
                          width: shown.w * size.width, height: shown.h * size.height)
        return ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.teal.opacity(0.08))
                .overlay(Rectangle().stroke(Color.teal, lineWidth: 1.5))
                .contentShape(Rectangle())
                .gesture(drag(of: clip) { t in
                    position.moved(dx: t.width / size.width, dy: t.height / size.height)
                })
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.teal)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle().inset(by: -6))
                .gesture(drag(of: clip) { t in
                    position.resized(toWidth: position.w + t.width / size.width)
                })
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .help("Drag to move, drag the corner to resize")
    }

    private func drag(of clip: Project.TimelineClip,
                      to position: @escaping (CGSize) -> Project.MediaPosition) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { draft = position($0.translation) }
            .onEnded { value in
                let final = position(value.translation)
                Task {
                    _ = await editor.updateClip(clipId: clip.id, inTrackId: selected.trackId, position: final)
                    draft = nil
                }
            }
    }
}
