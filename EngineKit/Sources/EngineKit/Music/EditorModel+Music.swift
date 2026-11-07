//
//  EditorModel+Music.swift
//  EngineKit
//
//  Rendering and placing generated music, for every caller: the editor and the MCP tools.
//  Render first and edit after, so the open editor is not held while a score plays out.
//

import Foundation

public struct RenderedMusic: Sendable {
    public let file: URL
    public let seconds: TimeInterval

    /// `file` must be in the project's assets: a render, or an imported song.
    public init(file: URL, seconds: TimeInterval) {
        self.file = file
        self.seconds = seconds
    }

    var path: String { RenderedAssets.projectPath(of: file) }
}

extension Project.TimelineClip {
    public var isGeneratedMusic: Bool { RenderedAssets.renderedPath(of: self, as: .music) != nil }
}

extension Project.Timeline {
    public typealias MusicPiece = (track: Project.TimelineTrack, clip: Project.TimelineClip)

    public var musicPieces: [MusicPiece] {
        audioTracks.flatMap { track in track.clips.filter(\.isGeneratedMusic).map { (track, $0) } }
    }
}

extension MusicRenderer {
    /// Renders into the project's assets with its source beside it.
    public static func renderAsset(_ source: MusicSource, in directory: URL) async throws -> RenderedMusic {
        let (file, seconds) = try await RenderedAssets.render(source, in: directory) { file in
            try await render(source, to: file)
        }
        return RenderedMusic(file: file, seconds: seconds)
    }
}

extension MusicSource {
    /// How long a piece starting at `start` should run: to the end of the picture, or of everything
    /// when there is no picture. Music already there does not count, or it could never shrink.
    public static func fittedDuration(from start: TimeInterval, in timeline: Project.Timeline) -> TimeInterval? {
        let end = timeline.tracks.filter { $0.type != .audio }.flatMap(\.clips).map(\.timelineOut).max() ?? timeline.duration
        return end > start ? min(end - start, MusicRenderer.maxDuration) : nil
    }

    /// What a clip was made from. Nil for imported audio, and for a render whose sidecar is gone.
    public static func load(of clip: Project.TimelineClip, in directory: URL) -> MusicSource? {
        RenderedAssets.renderedPath(of: clip, as: .music).flatMap { load(for: directory.appendingPathComponent($0)) }
    }

    /// The piece a clip replaced, while its files are still there.
    public static func previous(of clip: Project.TimelineClip, in directory: URL) -> (path: String, source: MusicSource)? {
        guard let path = load(of: clip, in: directory)?.previous,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path),
              let source = load(for: directory.appendingPathComponent(path)) else { return nil }
        return (path, source)
    }
}

extension EditorModel {
    /// Puts music on a free Music track, or a new one that ducks by `ducking`.
    public func addMusic(_ music: RenderedMusic, at start: TimeInterval, volume: Double = MusicSource.defaultVolume,
                         ducking: Double = MusicSource.defaultDucking) async -> EditorResult {
        if let error = EditorValidation.validateUnitValue(ducking, field: "ducking") { return .failure(error) }
        let track = freeTrack(.audio, named: MusicSource.trackName, from: start, to: start + music.seconds)
        return await addAudioClip(path: music.path, duration: music.seconds, at: start, trackName: MusicSource.trackName,
                                  volume: volume, onTrack: track, duckingOnNewTrack: ducking)
    }

    /// Swaps a clip's music in place and remembers the piece it replaced. RenderedAssets keeps that one
    /// file; anything older goes when the project next opens, once no undo can reach it.
    public func replaceMusic(clipId: String, inTrackId trackId: UUID, with music: RenderedMusic) async -> EditorResult {
        let replaced = musicClip(clipId, inTrackId: trackId).flatMap { RenderedAssets.renderedPath(of: $0, as: .music) }
        let result = await replaceClipContent(clipId: clipId, inTrackId: trackId,
                                              content: .audio(Project.AudioClipRef(path: music.path, duration: music.seconds)))
        if result.getProject() != nil, var source = MusicSource.load(for: music.file) {
            source.previous = replaced
            try? source.save(for: music.file)
        }
        return result
    }

    /// Goes back to the piece a clip replaced without rendering. Doing it again returns, so the two can be compared.
    public func swapMusicWithPrevious(clipId: String, inTrackId trackId: UUID, in directory: URL) async -> EditorResult {
        guard let clip = musicClip(clipId, inTrackId: trackId), let (path, source) = MusicSource.previous(of: clip, in: directory) else {
            return .failure(.invalidClipContent(reason: "This piece has no previous version"))
        }
        return await replaceMusic(clipId: clipId, inTrackId: trackId,
                                  with: RenderedMusic(file: directory.appendingPathComponent(path), seconds: source.options.duration))
    }

    private func musicClip(_ clipId: String, inTrackId trackId: UUID) -> Project.TimelineClip? {
        projectRef.timeline.tracks.first { $0.id == trackId }?.clips.first { $0.id == clipId }
    }
}
