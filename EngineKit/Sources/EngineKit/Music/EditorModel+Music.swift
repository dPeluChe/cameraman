//
//  EditorModel+Music.swift
//  EngineKit
//
//  Rendering and placing generated music, for every caller: the editor and the MCP tools.
//  Render first and edit after, so the open editor is not held while a score plays out.
//

import AVFoundation
import Foundation

public struct RenderedMusic: Sendable {
    public let file: URL
    public let seconds: TimeInterval

    var path: String { RenderedAssets.projectPath(of: file) }

    /// Copies a song into the project's assets to place like a render, cut to `length` when it is longer.
    /// Remove the file if placing it fails.
    public static func importSong(from url: URL, into directory: URL, upTo length: TimeInterval?) async throws -> RenderedMusic {
        let file = directory.appendingPathComponent(try ProjectLibrary.stageAsset(from: url, intoProjectDirectory: directory))
        let seconds = (try? await AVURLAsset(url: file).load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0 else {
            RenderedAssets.remove(file)
            throw MusicError.invalidOptions("\(url.lastPathComponent) has no audio")
        }
        return RenderedMusic(file: file, seconds: min(seconds, length ?? seconds))
    }
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

    /// Renders back-to-back pieces covering `source.options.duration`, each within the render limit.
    /// The seed steps per piece so neighbours differ. Nothing is left behind if one fails.
    public static func renderChain(_ source: MusicSource, in directory: URL) async throws -> [RenderedMusic] {
        var pieces: [RenderedMusic] = []
        do {
            for (index, length) in MusicSource.sections(of: source.options.duration).enumerated() {
                var piece = source
                piece.options.duration = length
                piece.options.seed += index
                pieces.append(try await renderAsset(piece, in: directory))
            }
        } catch {
            pieces.forEach { RenderedAssets.remove($0.file) }
            throw error
        }
        return pieces
    }
}

extension MusicSource {
    /// How long music starting at `start` should run: to the end of the picture, or of everything
    /// when there is no picture. Music already there does not count, or it could never shrink.
    /// Longer than one render allows on long videos: see `sections(of:)`.
    public static func fittedDuration(from start: TimeInterval, in timeline: Project.Timeline) -> TimeInterval? {
        let end = timeline.tracks.filter { $0.type != .audio }.flatMap(\.clips).map(\.timelineOut).max() ?? timeline.duration
        return end > start ? end - start : nil
    }

    /// Equal lengths within the render limit that add up to `length`, so no piece is a short tail.
    public static func sections(of length: TimeInterval) -> [TimeInterval] {
        let count = max(1, Int((length / MusicRenderer.maxDuration).rounded(.up)))
        return Array(repeating: length / Double(count), count: count)
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

    /// Places pieces back to back from `start` as one edit: all of them or none.
    public func addMusic(_ pieces: [RenderedMusic], at start: TimeInterval, volume: Double = MusicSource.defaultVolume,
                         ducking: Double = MusicSource.defaultDucking) async -> EditorResult {
        let before = projectRef
        var result = EditorResult.failure(.invalidClipContent(reason: "No music to add"))
        var time = start
        for piece in pieces {
            result = await addMusic(piece, at: time, volume: volume, ducking: ducking)
            guard result.getProject() != nil else {
                projectRef = before
                return result
            }
            time += piece.seconds
        }
        return result
    }

    private func musicClip(_ clipId: String, inTrackId trackId: UUID) -> Project.TimelineClip? {
        projectRef.timeline.tracks.first { $0.id == trackId }?.clips.first { $0.id == clipId }
    }
}
