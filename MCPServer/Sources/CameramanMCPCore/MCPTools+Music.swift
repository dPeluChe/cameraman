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
        guard let length = args.optNum("duration") ?? MusicSource.fittedDuration(from: at, in: project.timeline) else {
            throw MCPToolError("The picture ends before 'at'. Pass 'duration'.")
        }
        let source = try Self.musicSource(args, editing: nil, duration: length)
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let music = try await MusicRenderer.renderAsset(source, in: directory)

        return try await RenderedAssets.removing(music.file) {
            var added: EditorResultInfo?
            let updated = try await mutate(args) { editor in
                let result = await editor.addMusic(music, at: at, volume: volume, ducking: ducking)
                if case .successWithInfo(_, let info) = result { added = info }
                return result
            }
            var extra = Self.clipIds(added)
            let envelopes = AudioDucking.envelopes(for: updated, directory: directory)
            extra["speechDucking"] = (extra["clipId"] as? String).map { envelopes[$0] != nil } ?? false
            return try summary("Added music (\(String(format: "%.1f", music.seconds))s) at \(at)s", updated, extra: extra)
        }
    }

    func updateMusic(_ args: [String: Any]) async throws -> String {
        let (project, track, clip) = try await resolveClip(args)
        guard clip.isGeneratedMusic else {
            throw MCPToolError("That clip is not generated music.")
        }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let saved = MusicSource.load(of: clip, in: directory)
        let source = try Self.musicSource(args, editing: saved, duration: clip.duration)
        let music = try await MusicRenderer.renderAsset(source, in: directory)

        return try await RenderedAssets.removing(music.file) {
            let updated = try await mutate(args) { await $0.replaceMusic(clipId: clip.id, inTrackId: track.id, with: music) }
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
}
