//
//  MCPTools+Music.swift
//  cameraman-mcp
//
//  add_music, update_music: render a score to an audio file and place it as a clip. Rendering runs
//  in a web view, so like motion graphics it only works when the app hosts the server.
//

import Foundation
import EngineKit

extension MCPTools {

    func addMusic(_ args: [String: Any]) async throws -> String {
        let at = args.optNum("at") ?? 0
        guard at >= 0 else { throw MCPToolError("'at' must be 0 or later.") }
        let volume = args.optNum("volume") ?? MusicSource.defaultVolume
        guard (0...1).contains(volume) else { throw MCPToolError("'volume' must be between 0 and 1.") }
        let ducking = args.optNum("ducking") ?? MusicSource.defaultDucking
        if let error = EditorValidation.validateUnitValue(ducking, field: "ducking") { throw MCPToolError(error.localizedDescription) }
        let project = try await loadProject(args)
        let remaining = project.timeline.duration - at
        guard let length = args.optNum("duration") ?? (remaining > 0 ? min(remaining, MusicRenderer.maxDuration) : nil) else {
            throw MCPToolError("The timeline ends before 'at'. Pass 'duration'.")
        }
        let source = try Self.musicSource(args, editing: nil, duration: length)
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let (file, seconds) = try await renderMusic(source, directory)

        return try await RenderedAssets.removing(file) {
            var added: EditorResultInfo?
            let updated = try await mutate(args) { editor in
                let track = await editor.freeTrack(.audio, named: MusicSource.trackName, from: at, to: at + seconds)
                let result = await editor.addAudioClip(path: "assets/\(file.lastPathComponent)", duration: seconds, at: at,
                                                       trackName: MusicSource.trackName, volume: volume, onTrack: track,
                                                       duckingOnNewTrack: ducking)
                if case .successWithInfo(_, let info) = result { added = info }
                return result
            }
            var extra = Self.clipIds(added)
            let envelopes = AudioDucking.envelopes(for: updated, directory: directory)
            extra["speechDucking"] = (extra["clipId"] as? String).map { envelopes[$0] != nil } ?? false
            return try summary("Added music (\(String(format: "%.1f", seconds))s) at \(at)s", updated, extra: extra)
        }
    }

    func updateMusic(_ args: [String: Any]) async throws -> String {
        let (project, track, clip) = try await resolveClip(args)
        guard let path = RenderedAssets.renderedPath(of: clip, as: .music) else {
            throw MCPToolError("That clip is not generated music.")
        }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let saved = MusicSource.load(for: directory.appendingPathComponent(path))
        let source = try Self.musicSource(args, editing: saved, duration: clip.duration)
        let (file, seconds) = try await renderMusic(source, directory)

        return try await RenderedAssets.removing(file) {
            let content = Project.ClipContent.audio(Project.AudioClipRef(path: "assets/\(file.lastPathComponent)", duration: seconds))
            let updated = try await mutate(args) {
                await $0.replaceClipContent(clipId: clip.id, inTrackId: track.id, content: content,
                                            ending: clip.timelineIn + seconds / clip.speed)
            }
            // The old file stays for undo; RenderedAssets removes it when the project next opens.
            return try summary("Updated music \(clip.id)", updated)
        }
    }

    /// The new source: `args` over what was saved.
    static func musicSource(_ args: [String: Any], editing saved: MusicSource?, duration: TimeInterval) throws -> MusicSource {
        guard let score = try musicScore(args) ?? saved?.score else { throw MCPToolError("Pass 'style' or 'code'.") }
        var options = saved?.options ?? MusicRenderOptions(duration: duration)
        if let duration = args.optNum("duration") { options.duration = duration }
        if let seed = args.optNum("seed") { options.seed = Int(seed) }
        if let key = args.optStr("key") { options.key = key }
        if let bpm = args.optNum("bpm") { options.bpm = bpm }
        if let intensity = args.optNum("intensity") { options.intensity = intensity }
        return MusicSource(score: score, options: options)
    }

    private static func musicScore(_ args: [String: Any]) throws -> MusicScore? {
        switch (args.optStr("style"), args.optStr("code")) {
        case (.some, .some):
            throw MCPToolError("Pass either 'style' or 'code', not both.")
        case (let name?, nil):
            guard let style = MusicStyle(rawValue: name) else {
                throw MCPToolError("Unknown style '\(name)'. Use: \(MusicStyle.allCases.map(\.rawValue).joined(separator: ", ")), or pass 'code'.")
            }
            return .style(style)
        case (nil, let code?):
            return .code(code)
        case (nil, nil):
            return nil
        }
    }

    /// Renders before the edit starts, so the open editor is not held while this runs.
    private func renderMusic(_ source: MusicSource, _ directory: URL) async throws -> (file: URL, output: TimeInterval) {
        try await RenderedAssets.render(source, in: directory) { file in
            try await MusicRenderer.render(source, to: file)
        }
    }
}
