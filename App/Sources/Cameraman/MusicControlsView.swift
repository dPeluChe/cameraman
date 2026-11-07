//
//  MusicControlsView.swift
//  Cameraman
//
//  The Music tool: compose a background piece and change it. Same engine calls as add_music and
//  update_music, so what an agent makes can be edited here and the other way round.
//

import AVFoundation
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

/// Outlives the panel and the editor: collapsing the tool keeps a render, and an agent reload swaps the editor under it.
@MainActor
final class MusicPanelModel: ObservableObject {
    @Published private(set) var isRendering = false
    @Published private(set) var errorMessage: String?
    /// The style whose sample is loading or playing.
    @Published private(set) var sampleStyle: MusicStyle?
    @Published private var samplePlayer: AVAudioPlayer?
    private var sampleTask: Task<Void, Never>?

    var isLoadingSample: Bool { sampleStyle != nil && samplePlayer == nil }

    private let editor: () -> ProjectEditor?
    private let directory: () -> URL?

    init(editor: @escaping () -> ProjectEditor?, directory: @escaping () -> URL?) {
        self.editor = editor
        self.directory = directory
    }

    var projectDirectory: URL? { directory() }

    /// Renders outside the edit, then drops the file if the edit is refused or the project closed.
    func compose(_ source: MusicSource, place: @escaping (ProjectEditor, RenderedMusic) async -> EditorResult) async {
        guard !isRendering, let directory = directory() else { return }
        isRendering = true
        errorMessage = nil
        defer { isRendering = false }
        do {
            let music = try await MusicRenderer.renderAsset(source, in: directory)
            guard let editor = editor() else { return RenderedAssets.remove(music.file) }
            let result = await place(editor, music)
            if case .failure = result { RenderedAssets.remove(music.file) }
            report(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func report(_ result: EditorResult) {
        if case .failure(let error) = result {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = nil
        }
    }

    func report(_ message: String) { errorMessage = message }

    /// Plays a style's sample, or stops it when it is the one playing.
    func toggleSample(_ style: MusicStyle) {
        let wasPlaying = sampleStyle == style
        stopSample()
        guard !wasPlaying else { return }
        sampleStyle = style
        sampleTask = Task {
            do {
                let player = try AVAudioPlayer(contentsOf: try await MusicRenderer.sample(of: style))
                try Task.checkCancellation()
                samplePlayer = player
                player.play()
                try await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
                stopSample()
            } catch is CancellationError {
            } catch {
                stopSample()
                report(error.localizedDescription)
            }
        }
    }

    func stopSample() {
        sampleTask?.cancel()
        sampleTask = nil
        samplePlayer?.stop()
        samplePlayer = nil
        sampleStyle = nil
    }

    /// Copies a song into the project and lays it on a Music track, cut to the picture.
    func importSong(from url: URL) async {
        guard !isRendering, let directory = directory(), let editor = editor() else { return }
        isRendering = true
        defer { isRendering = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let length = MusicSource.fittedDuration(from: 0, in: editor.project.timeline)
            let music = try await RenderedMusic.importSong(from: url, into: directory, upTo: length)
            let result = await editor.addMusic(music, at: 0)
            if case .failure = result { RenderedAssets.remove(music.file) }
            report(result)
        } catch {
            report(error.localizedDescription)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var model: MusicPanelModel
    @Binding var showTranscriptionModal: Bool

    @State private var source: MusicSource?
    @State private var previous: MusicSource?
    @State private var hasTranscript = false
    /// Settings for the next piece; an existing piece answers from its source.
    @State private var style = MusicStyle.lofi
    @State private var intensity = 0.5
    @State private var showImporter = false

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3)
    private let sliderLabelWidth: CGFloat = 96

    private var current: Project.Timeline.MusicPiece? {
        let pieces = editor.project.timeline.musicPieces
        return pieces.first { $0.clip.id == editor.selectedClip?.clip.id } ?? pieces.first
    }

    private var reloadKey: String {
        "\(ObjectIdentifier(editor).hashValue)|\(current.flatMap { RenderedAssets.renderedPath(of: $0.clip, as: .music) } ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            styleGrid
            slider("Intensity", value: source?.options.intensity ?? intensity) { value in
                if current == nil { intensity = value } else { change { $0.options.intensity = value } }
            }
            .disabled(current != nil && source == nil)

            if let current {
                pieceControls(current)
            } else {
                Button { generate() } label: { PanelActionLabel("Generate Music", icon: "music.note") }
                    .buttonStyle(.borderedProminent)
            }
            Button { showImporter = true } label: { PanelActionLabel("Import Audio File…", icon: "square.and.arrow.down") }
                .help("Use your own song; it goes on a Music track and lowers under the voice")
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
        .disabled(model.isRendering)
        .task(id: reloadKey) { reload() }
        .onDisappear { model.stopSample() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { Task { await model.importSong(from: url) } }
        }
        .onChangeCompat(of: showTranscriptionModal) { isOpen in
            if !isOpen { reload() }
        }
    }

    private var styleGrid: some View {
        LazyVGrid(columns: tileColumns, spacing: Spacing.xs) {
            ForEach(MusicStyle.allCases, id: \.self) { tile in
                FormatButton(title: tile.title, icon: tile.icon, isSelected: isCurrent(tile)) { pick(tile) }
                    .overlay(alignment: .topTrailing) { sampleButton(tile) }
            }
        }
    }

    private func sampleButton(_ tile: MusicStyle) -> some View {
        let isActive = model.sampleStyle == tile
        return Button { model.toggleSample(tile) } label: {
            Group {
                if isActive, model.isLoadingSample {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isActive ? "stop.circle.fill" : "play.circle")
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .padding(3)
        .help(isActive ? "Stop" : "Listen to a sample of \(tile.title)")
    }

    private func isCurrent(_ tile: MusicStyle) -> Bool {
        (source?.score ?? .style(style)) == .style(tile)
    }

    @ViewBuilder
    private func pieceControls(_ piece: Project.Timeline.MusicPiece) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 2) {
            Text(title(of: source)).font(.subheadline)
            Text("\(PreviewPlayerViewModel.formatTime(piece.clip.timelineIn)) – \(PreviewPlayerViewModel.formatTime(piece.clip.timelineOut))")
                .font(.caption).foregroundStyle(.secondary)
            if editor.project.timeline.musicPieces.count > 1 {
                Text("Select another piece on the timeline to edit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Button { change { $0.options.seed += 1 } } label: { PanelActionLabel("Another Variation", icon: "shuffle") }
            .disabled(source == nil)
        if let previous {
            Button { swapWithPrevious(piece) } label: {
                PanelActionLabel("Use Previous: \(title(of: previous))", icon: "arrow.left.arrow.right")
            }
        }

        slider("Volume", value: piece.clip.volume ?? 1) { volume in
            Task { await model.report(editor.updateClip(clipId: piece.clip.id, inTrackId: piece.track.id, volume: volume)) }
        }
        slider("Lower under voice", value: 1 - (piece.track.duckingLevel ?? 1)) { amount in
            Task { await model.report(editor.setTrackDucking(trackId: piece.track.id, level: 1 - amount)) }
        }
        if !hasTranscript, piece.track.duckingLevel != nil {
            HStack {
                Text("Needs a transcript to work.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Transcribe…") { showTranscriptionModal = true }.controlSize(.small)
            }
        }

        HStack {
            Button("Fit to Video") {
                if let length = fitLength(piece) { change { $0.options.duration = length } }
            }
            .disabled(source == nil || fitLength(piece) == nil)
            Spacer()
            Button("Remove", role: .destructive) {
                Task { await model.report(editor.removeClip(clipId: piece.clip.id, fromTrackId: piece.track.id)) }
            }
        }
    }

    private func slider(_ title: String, value: Double, commit: @escaping (Double) -> Void) -> DraftSlider {
        DraftSlider(label: title, range: 0...1, step: nil, current: value, labelWidth: sliderLabelWidth,
                    display: { "\(Int($0 * 100))%" }, commit: commit)
    }

    private func title(of source: MusicSource?) -> String {
        switch source?.score {
        case .style(let style)?: return style.title
        case .code?: return "Custom score"
        case nil: return "Music"
        }
    }

    private func fitLength(_ piece: Project.Timeline.MusicPiece) -> TimeInterval? {
        guard let length = MusicSource.fittedDuration(from: piece.clip.timelineIn, in: editor.project.timeline),
              abs(length - piece.clip.duration) > 0.1 else { return nil }
        return length
    }

    private func reload() {
        guard let directory = model.projectDirectory else { return }
        let transcript = directory.appendingPathComponent(TranscriptionEngine.Transcript.relativePath)
        hasTranscript = FileManager.default.fileExists(atPath: transcript.path)
        source = current.flatMap { MusicSource.load(of: $0.clip, in: directory) }
        previous = current.flatMap { MusicSource.previous(of: $0.clip, in: directory)?.source }
    }

    private func generate() {
        guard let duration = MusicSource.fittedDuration(from: 0, in: editor.project.timeline) else {
            return model.report("Add a video first: the music follows its length.")
        }
        let options = MusicRenderOptions(duration: duration, seed: Int.random(in: 1...9999), intensity: intensity)
        let source = MusicSource(score: .style(style), options: options)
        Task { await model.compose(source) { editor, music in await editor.addMusic(music, at: 0) } }
    }

    private func pick(_ tile: MusicStyle) {
        guard let piece = current else { return style = tile }
        guard !isCurrent(tile) else { return }
        // A style is enough to start over when the sidecar is gone.
        var next = source ?? MusicSource(score: .style(tile), options: MusicRenderOptions(duration: piece.clip.duration, intensity: intensity))
        next.score = .style(tile)
        replace(piece, with: next)
    }

    private func change(_ edit: (inout MusicSource) -> Void) {
        guard var next = source, let piece = current else { return }
        edit(&next)
        replace(piece, with: next)
    }

    private func swapWithPrevious(_ piece: Project.Timeline.MusicPiece) {
        guard let directory = model.projectDirectory else { return }
        Task { await model.report(editor.swapMusicWithPrevious(clipId: piece.clip.id, inTrackId: piece.track.id, in: directory)) }
    }

    private func replace(_ piece: Project.Timeline.MusicPiece, with source: MusicSource) {
        let clipId = piece.clip.id, trackId = piece.track.id
        Task {
            await model.compose(source) { editor, music in
                await editor.replaceMusic(clipId: clipId, inTrackId: trackId, with: music)
            }
        }
    }
}
