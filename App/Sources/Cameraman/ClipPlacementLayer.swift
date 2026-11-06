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

    /// Only imported video renders a placement, and only while the playhead is on it.
    private var clip: Project.TimelineClip? {
        guard let clip = editor.liveSelectedClip, case .video = clip.content else { return nil }
        let time = playerViewModel.currentTime
        return time >= clip.timelineIn && time <= clip.timelineOut ? clip : nil
    }

    var body: some View {
        GeometryReader { geometry in
            if let clip {
                placement(of: clip, position: clip.position ?? Project.MediaPosition(), in: geometry.size)
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
                .gesture(drag(of: clip, in: size) { position.moved(dx: $0.x, dy: $0.y) })
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.teal)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle().inset(by: -6))
                .gesture(drag(of: clip, in: size) { position.resized(toWidth: position.w + $0.x) })
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .help("Drag to move, drag the corner to resize")
    }

    private func drag(of clip: Project.TimelineClip, in size: CGSize,
                      to position: @escaping (CGPoint) -> Project.MediaPosition) -> some Gesture {
        let target = { (translation: CGSize) in
            position(OverlayCanvasGeometry.normalizedTranslation(translation, canvasSize: size))
        }
        return DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { draft = target($0.translation) }
            .onEnded { value in
                let final = target(value.translation)
                Task {
                    _ = await editor.updateClip(clipId: clip.id, inTrackId: selected.trackId, position: final)
                    draft = nil
                }
            }
    }
}
