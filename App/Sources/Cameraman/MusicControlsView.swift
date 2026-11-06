//
//  MusicControlsView.swift
//  Cameraman
//
//  The Music tool: compose a background piece and change it. Same engine calls as add_music and
//  update_music, so what an agent makes can be edited here and the other way round.
//

import Combine
import SwiftUI
import EngineKit

private extension MusicStyle {
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .ambient: return "cloud"
        case .lofi: return "headphones"
        case .corporate: return "building.2"
        case .tech: return "cpu"
        case .cinematic: return "film"
        case .acoustic: return "guitars"
        }
    }
}

@MainActor
private final class MusicPanelModel: ObservableObject {
    @Published private(set) var isRendering = false
    @Published var errorMessage: String?

    /// Renders outside the edit, then drops the file if the edit is refused.
    func compose(_ source: MusicSource, in directory: URL, place: (RenderedMusic) async -> EditorResult) async {
        guard !isRendering else { return }
        isRendering = true
        errorMessage = nil
        defer { isRendering = false }
        do {
            let music = try await MusicRenderer.renderAsset(source, in: directory)
            if case .failure(let error) = await place(music) {
                RenderedAssets.remove(music.file)
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var showTranscriptionModal: Bool

    @StateObject private var model = MusicPanelModel()
    @State private var directory: URL?
    @State private var source: MusicSource?
    @State private var hasTranscript = false
    @State private var style = MusicStyle.lofi
    @State private var intensity = 0.5

    private typealias Piece = (track: Project.TimelineTrack, clip: Project.TimelineClip)
    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3)

    private var pieces: [Piece] {
        editor.project.timeline.audioTracks.flatMap { track in
            track.clips.filter { RenderedAssets.renderedPath(of: $0, as: .music) != nil }.map { (track, $0) }
        }
    }

    /// The piece selected on the timeline, or the first one.
    private var current: Piece? {
        pieces.first { $0.clip.id == editor.selectedClip?.clip.id } ?? pieces.first
    }

    private var reloadKey: String {
        let path = current.flatMap { RenderedAssets.renderedPath(of: $0.clip, as: .music) } ?? ""
        return "\(path)|\(showTranscriptionModal)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            styleGrid
            labeledSlider("Intensity", value: intensity) { value in
                intensity = value
                if current != nil { change { $0.options.intensity = value } }
            }
            if let current {
                pieceControls(current)
            } else {
                Button { generate() } label: { Text("Generate Music").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRendering || directory == nil)
            }
            if model.isRendering {
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Composing…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: reloadKey) { await reload() }
    }

    private var styleGrid: some View {
        LazyVGrid(columns: tileColumns, spacing: Spacing.xs) {
            ForEach(MusicStyle.allCases, id: \.self) { tile in
                Button {
                    style = tile
                    if current != nil { change { $0.score = .style(tile) } }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tile.icon)
                        Text(tile.title).font(.caption2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isCurrent(tile) ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: Radius.small)
                        .stroke(isCurrent(tile) ? Color.accentColor : Color.secondary.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(model.isRendering)
            }
        }
    }

    private func isCurrent(_ tile: MusicStyle) -> Bool {
        if case .code? = source?.score, current != nil { return false }
        return tile == style
    }

    @ViewBuilder
    private func pieceControls(_ piece: Piece) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 2) {
            Text(pieceTitle).font(.subheadline)
            Text("\(clock(piece.clip.timelineIn)) – \(clock(piece.clip.timelineOut))")
                .font(.caption).foregroundStyle(.secondary)
            if pieces.count > 1 {
                Text("\(pieces.count) pieces. Select one on the timeline to edit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Button { change { $0.options.seed += 1 } } label: { Text("Another Variation").frame(maxWidth: .infinity) }
            .disabled(model.isRendering)

        labeledSlider("Volume", value: piece.clip.volume ?? 1) { volume in
            Task { await report(editor.updateClip(clipId: piece.clip.id, inTrackId: piece.track.id, volume: volume)) }
        }
        duckingControl(piece.track)

        HStack {
            Button("Fit to Video") { fit(piece) }
                .disabled(model.isRendering || !canFit(piece))
            Spacer()
            Button("Remove", role: .destructive) {
                Task { await report(editor.removeClip(clipId: piece.clip.id, fromTrackId: piece.track.id)) }
            }
            .disabled(model.isRendering)
        }
    }

    @ViewBuilder
    private func duckingControl(_ track: Project.TimelineTrack) -> some View {
        labeledSlider("Lower under voice", value: 1 - (track.duckingLevel ?? 1)) { amount in
            Task { await report(editor.setTrackDucking(trackId: track.id, level: 1 - amount)) }
        }
        if !hasTranscript, track.duckingLevel != nil {
            HStack {
                Text("Needs a transcript to work.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Transcribe…") { showTranscriptionModal = true }.controlSize(.small)
            }
        }
    }

    private func labeledSlider(_ title: String, value: Double, commit: @escaping (Double) -> Void) -> some View {
        CommitSlider(title: title, value: value, isDisabled: model.isRendering, commit: commit)
    }

    private var pieceTitle: String {
        switch source?.score {
        case .style(let style)?: return style.title
        case .code?: return "Custom score"
        case nil: return "Music"
        }
    }

    private func clock(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }

    private func canFit(_ piece: Piece) -> Bool {
        guard let length = MusicSource.fittedDuration(from: piece.clip.timelineIn, in: editor.project.timeline) else { return false }
        return abs(length - piece.clip.duration) > 0.1
    }

    private func report(_ result: EditorResult) {
        if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
    }

    private func reload() async {
        let id = editor.project.projectId
        guard let found = try? await ProjectLibrary.shared.getProjectDirectory(projectId: id) else { return }
        directory = found
        hasTranscript = (try? TranscriptionEngine.Transcript.load(fromProject: found)) != nil
        source = current.flatMap { MusicSource.load(of: $0.clip, in: found) }
        guard let source else { return }
        intensity = source.options.intensity
        if case .style(let saved) = source.score { style = saved }
    }

    private func generate() {
        guard let directory else { return }
        guard let duration = MusicSource.fittedDuration(from: 0, in: editor.project.timeline) else {
            model.errorMessage = "Add a video first: the music follows its length."
            return
        }
        let options = MusicRenderOptions(duration: duration, seed: Int.random(in: 1...9999), intensity: intensity)
        Task {
            await model.compose(MusicSource(score: .style(style), options: options), in: directory) { music in
                await editor.addMusic(music, at: 0)
            }
        }
    }

    /// Renders the current piece again with `edit` applied, keeping its place on the timeline.
    private func change(_ edit: (inout MusicSource) -> Void) {
        guard let directory, let piece = current else { return }
        var next = source ?? MusicSource(score: .style(style), options: MusicRenderOptions(duration: piece.clip.duration, intensity: intensity))
        edit(&next)
        let source = next
        Task {
            await model.compose(source, in: directory) { music in
                await editor.replaceMusic(clipId: piece.clip.id, inTrackId: piece.track.id, with: music)
            }
        }
    }

    private func fit(_ piece: Piece) {
        guard let length = MusicSource.fittedDuration(from: piece.clip.timelineIn, in: editor.project.timeline) else { return }
        change { $0.options.duration = length }
    }
}

/// Commits on release, so a drag is one undo step and one render.
private struct CommitSlider: View {
    let title: String
    let value: Double
    let isDisabled: Bool
    let commit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int((draft ?? value) * 100))%").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: 0...1) { editing in
                guard !editing, let draft else { return }
                self.draft = nil
                if abs(draft - value) > 0.001 { commit(draft) }
            }
            .controlSize(.small)
            .disabled(isDisabled)
        }
    }
}
