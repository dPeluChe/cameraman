//
//  TimelineView+VideoClipInspector.swift
//  App
//
//  Inline inspector shown when an imported-video clip is selected:
//  3x3 position grid + size + fullscreen reset + remove.
//

import SwiftUI
import EngineKit

extension TimelineView {

    /// Fresh copy of the selected clip from the live project (selection holds a snapshot).
    private var liveSelectedVideoClip: Project.TimelineClip? {
        guard let selected = selectedVideoClip,
              let track = editor.project.timeline.tracks.first(where: { $0.id == selected.trackId })
        else { return nil }
        return track.clips.first { $0.id == selected.clip.id }
    }

    @ViewBuilder
    var videoClipInspector: some View {
        if let selected = selectedVideoClip, let clip = liveSelectedVideoClip {
            HStack(spacing: 14) {
                Label(videoClipName(clip), systemImage: "film")
                    .font(.caption)
                    .lineLimit(1)

                Divider().frame(height: 18)

                positionGrid(for: clip, trackId: selected.trackId)

                Picker("", selection: sizeBinding(for: clip, trackId: selected.trackId)) {
                    Text("S").tag(0.25)
                    Text("M").tag(0.35)
                    Text("L").tag(0.5)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .help("PiP size")

                Button("Fullscreen") {
                    apply(position: Project.MediaPosition(x: 0, y: 0, w: 1, h: 1), to: clip, trackId: selected.trackId)
                }
                .controlSize(.small)
                .help("Cover the whole canvas")

                // Effects live in a popover so the row stays one line tall — adding
                // effects never pushes the timeline down.
                Button {
                    showVideoClipEffects.toggle()
                } label: {
                    Label("Effects", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .help("Color filters, blur and audio pitch")
                .popover(isPresented: $showVideoClipEffects, arrowEdge: .bottom) {
                    VideoClipEffectsView(editor: editor, clipId: clip.id, trackId: selected.trackId)
                        .padding(12)
                        .frame(width: 320)
                }

                Spacer()

                Button(role: .destructive) {
                    let trackId = selected.trackId
                    selectedVideoClip = nil
                    Task { _ = await editor.removeClip(clipId: clip.id, fromTrackId: trackId) }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Remove clip (and its row if empty)")

                Button {
                    selectedVideoClip = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.teal.opacity(0.12))
            )
        }
    }

    // MARK: - Controls

    private func positionGrid(for clip: Project.TimelineClip, trackId: UUID) -> some View {
        let margin = 0.04
        let size = currentPiPSize(of: clip)
        let cells: [(String, Double, Double)] = [
            ("arrow.up.left", margin, margin),
            ("arrow.up", (1 - size) / 2, margin),
            ("arrow.up.right", 1 - size - margin, margin),
            ("arrow.left", margin, (1 - size) / 2),
            ("circle", (1 - size) / 2, (1 - size) / 2),
            ("arrow.right", 1 - size - margin, (1 - size) / 2),
            ("arrow.down.left", margin, 1 - size - margin),
            ("arrow.down", (1 - size) / 2, 1 - size - margin),
            ("arrow.down.right", 1 - size - margin, 1 - size - margin)
        ]

        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 3), count: 3), spacing: 3) {
            ForEach(cells, id: \.0) { icon, x, y in
                Button {
                    apply(position: Project.MediaPosition(x: x, y: y, w: size, h: size), to: clip, trackId: trackId)
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .help("Position the video on the canvas (PiP)")
    }

    private func sizeBinding(for clip: Project.TimelineClip, trackId: UUID) -> Binding<Double> {
        Binding(
            get: { currentPiPSize(of: clip) },
            set: { newSize in
                // Keep the clip's center while resizing
                let pos = clip.position ?? .centered(w: newSize, h: newSize)
                let centerX = pos.x + pos.w / 2
                let centerY = pos.y + pos.h / 2
                let clamped = Project.MediaPosition(
                    x: min(max(0, centerX - newSize / 2), 1 - newSize),
                    y: min(max(0, centerY - newSize / 2), 1 - newSize),
                    w: newSize,
                    h: newSize
                )
                apply(position: clamped, to: clip, trackId: trackId)
            }
        )
    }

    /// In a 16:9 canvas, h == w (normalized) yields a 16:9 rect in pixels.
    private func currentPiPSize(of clip: Project.TimelineClip) -> Double {
        guard let pos = clip.position, pos.w < 0.999 else { return 0.35 }
        return pos.w
    }

    private func apply(position: Project.MediaPosition, to clip: Project.TimelineClip, trackId: UUID) {
        Task {
            _ = await editor.updateClip(clipId: clip.id, inTrackId: trackId, position: position)
        }
    }

    private func videoClipName(_ clip: Project.TimelineClip) -> String {
        if case .video(let ref) = clip.content {
            return (ref.path as NSString).lastPathComponent
        }
        return "Clip"
    }
}
