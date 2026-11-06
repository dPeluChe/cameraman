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

    var path: String { "assets/\(file.lastPathComponent)" }
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
    /// What a clip was made from. Nil for imported audio, and for a render whose sidecar is gone.
    public static func load(of clip: Project.TimelineClip, in directory: URL) -> MusicSource? {
        RenderedAssets.renderedPath(of: clip, as: .music).flatMap { load(for: directory.appendingPathComponent($0)) }
    }
}

extension EditorModel {
    /// Puts music on a free Music track, or a new one that ducks by `ducking`.
    public func addMusic(_ music: RenderedMusic, at start: TimeInterval, volume: Double = MusicSource.defaultVolume,
                         ducking: Double = MusicSource.defaultDucking) async -> EditorResult {
        let track = freeTrack(.audio, named: MusicSource.trackName, from: start, to: start + music.seconds)
        return await addAudioClip(path: music.path, duration: music.seconds, at: start, trackName: MusicSource.trackName,
                                  volume: volume, onTrack: track, duckingOnNewTrack: ducking)
    }

    /// Swaps a clip's music in place. The old file stays for undo; RenderedAssets removes it when the project next opens.
    public func replaceMusic(clipId: String, inTrackId trackId: UUID, with music: RenderedMusic) async -> EditorResult {
        guard let clip = projectRef.timeline.tracks.first(where: { $0.id == trackId })?.clips.first(where: { $0.id == clipId }) else {
            return .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        let content = Project.ClipContent.audio(Project.AudioClipRef(path: music.path, duration: music.seconds))
        return await replaceClipContent(clipId: clipId, inTrackId: trackId, content: content,
                                        ending: clip.timelineIn + music.seconds / clip.speed)
    }
}
