//
//  ClipPlacementLayer.swift
//  App
//
//  Drag the timeline-selected clip on the preview. The handle resizes it, keeping its shape.
//  The outline hugs what the clip draws, not its frame: a motion's frame is mostly transparent.
//

import SwiftUI
import AVFoundation
import EngineKit

struct ClipPlacementLayer: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    let selected: SelectedVideoClip
    let projectDirectory: URL?

    @State private var draft: Project.MediaPosition?
    @State private var shape: VideoContentShape?

    /// Only imported video renders a placement, and only while the playhead is on it.
    private var clip: Project.TimelineClip? {
        guard let clip = editor.liveSelectedClip, case .video = clip.content else { return nil }
        let time = playerViewModel.currentTime
        return time >= clip.timelineIn && time <= clip.timelineOut ? clip : nil
    }

    private var videoPath: String? {
        guard case .video(let ref)? = editor.liveSelectedClip?.content else { return nil }
        return ref.path
    }

    var body: some View {
        GeometryReader { geometry in
            if let clip {
                placement(of: clip, position: clip.position ?? Project.MediaPosition(), in: geometry.size)
            }
        }
        .clipped()
        .task(id: videoPath) {
            shape = nil
            guard let videoPath else { return }
            shape = await VideoContentShape.measure(url: URL(fileURLWithPath: videoPath, relativeTo: projectDirectory))
        }
    }

    private func placement(of clip: Project.TimelineClip, position: Project.MediaPosition, in size: CGSize) -> some View {
        let shown = draft ?? position
        let frame = CGRect(x: shown.x * size.width, y: shown.y * size.height,
                           width: shown.w * size.width, height: shown.h * size.height)
        let content = contentFraction(of: frame)
        let rect = CGRect(x: frame.minX + content.minX * frame.width, y: frame.minY + content.minY * frame.height,
                          width: content.width * frame.width, height: content.height * frame.height)
        return ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.teal.opacity(0.08))
                .overlay(Rectangle().stroke(Color.teal, lineWidth: 1.5))
                .contentShape(Rectangle())
                .gesture(drag(of: clip, in: size) { position.moved(dx: $0.x, dy: $0.y, keeping: content) })
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.teal)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle().inset(by: -6))
                .gesture(drag(of: clip, in: size) { translation in
                    position.resized(toWidth: position.w + translation.x / content.width, anchor: content.origin)
                        .moved(dx: 0, dy: 0, keeping: content)
                })
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .help("Drag to move, drag the corner to resize")
    }

    /// The clip's drawn area as fractions of its placement rect, which it aspect-fits into.
    private func contentFraction(of frame: CGRect) -> CGRect {
        guard let shape, frame.width > 0, frame.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let fit = AVMakeRect(aspectRatio: shape.naturalSize, insideRect: frame)
        return CGRect(x: (fit.minX - frame.minX + shape.bounds.minX * fit.width) / frame.width,
                      y: (fit.minY - frame.minY + shape.bounds.minY * fit.height) / frame.height,
                      width: shape.bounds.width * fit.width / frame.width,
                      height: shape.bounds.height * fit.height / frame.height)
    }

    private func drag(of clip: Project.TimelineClip, in size: CGSize,
                      to position: @escaping (CGPoint) -> Project.MediaPosition) -> some Gesture {
        let target = { (translation: CGSize) in
            position(OverlayCanvasGeometry.normalizedTranslation(translation, in: size))
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
