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

    static let musicTrackName = "Music"
    static let defaultMusicVolume = 0.25
    private static let maxScoreBytes = 256 * 1024

    func addMusic(_ args: [String: Any]) async throws -> String {
        try requireRenderingHost("add_music")
        let at = args.optNum("at") ?? 0
        guard at >= 0 else { throw MCPToolError("'at' must be 0 or later.") }
        let volume = args.optNum("volume") ?? Self.defaultMusicVolume
        guard (0...2).contains(volume) else { throw MCPToolError("'volume' must be between 0 and 2.") }
        let project = try await loadProject(args)
        let remaining = project.timeline.duration - at
        guard let length = args.optNum("duration") ?? (remaining > 0 ? min(remaining, MusicRenderer.maxDuration) : nil) else {
            throw MCPToolError("The timeline ends before 'at'. Pass 'duration'.")
        }
        let source = try Self.musicSource(args, editing: nil, defaultDuration: length)
        guard source.style != nil || source.code != nil else { throw MCPToolError("Pass 'style' or 'code'.") }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let (file, seconds) = try await renderMusic(source, directory)

        do {
            var added: EditorResultInfo?
            let updated = try await mutate(args) { editor in
                let track = await editor.freeTrack(.audio, named: Self.musicTrackName, from: at, to: at + seconds)
                let result = await editor.importAudioClip(path: "assets/\(file.lastPathComponent)", duration: seconds, at: at,
                                                          trackName: Self.musicTrackName, volume: volume, onTrack: track)
                if case .successWithInfo(_, let info) = result { added = info }
                return result
            }
            var extra: [String: Any] = [:]
            if case .clipAdded(let clipId, let trackId)? = added {
                extra["clipId"] = clipId
                extra["trackId"] = trackId.uuidString
            }
            return try summary("Added music (\(String(format: "%.1f", seconds))s) at \(at)s", updated, extra: extra)
        } catch {
            RenderedAssets.remove(file)
            throw error
        }
    }

    func updateMusic(_ args: [String: Any]) async throws -> String {
        try requireRenderingHost("update_music")
        let (project, track, clip) = try await resolveClip(args)
        guard case .audio(let ref) = clip.content, RenderedAssets.isRendered((ref.path as NSString).lastPathComponent, as: .music) else {
            throw MCPToolError("That clip is not generated music.")
        }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let saved = MusicSource.load(for: directory.appendingPathComponent(ref.path))
        let source = try Self.musicSource(args, editing: saved, defaultDuration: ref.duration)
        guard source.style != nil || source.code != nil else {
            throw MCPToolError("The score of this clip is gone. Pass 'style' or 'code'.")
        }
        let (file, seconds) = try await renderMusic(source, directory)

        do {
            let content = Project.ClipContent.audio(Project.AudioClipRef(path: "assets/\(file.lastPathComponent)", duration: seconds))
            let updated = try await mutate(args) {
                await $0.replaceClipContent(clipId: clip.id, inTrackId: track.id, content: content,
                                            ending: clip.timelineIn + seconds / clip.speed)
            }
            // The old file stays for undo; RenderedAssets removes it when the project next opens.
            return try summary("Updated music \(clip.id)", updated)
        } catch {
            RenderedAssets.remove(file)
            throw error
        }
    }

    /// The new source: `args` over what was saved.
    static func musicSource(_ args: [String: Any], editing saved: MusicSource?,
                            defaultDuration: TimeInterval) throws -> MusicSource {
        var source = saved ?? MusicSource(duration: defaultDuration)
        if let duration = args.optNum("duration") {
            guard (1...MusicRenderer.maxDuration).contains(duration) else {
                throw MCPToolError("'duration' must be between 1 and \(Int(MusicRenderer.maxDuration)) seconds. Add a second clip for longer videos.")
            }
            source.duration = duration
        }
        if let seed = args.optNum("seed") { source.seed = Int(seed) }
        if let key = args.optStr("key") { source.key = key }
        if let bpm = args.optNum("bpm") {
            guard (40...200).contains(bpm) else { throw MCPToolError("'bpm' must be between 40 and 200.") }
            source.bpm = bpm
        }
        if let intensity = args.optNum("intensity") {
            guard (0...1).contains(intensity) else { throw MCPToolError("'intensity' must be between 0 and 1.") }
            source.intensity = intensity
        }
        if let code = args.optStr("code") {
            guard args.optStr("style") == nil else { throw MCPToolError("Pass either 'style' or 'code', not both.") }
            guard code.utf8.count <= maxScoreBytes else { throw MCPToolError("'code' is larger than \(maxScoreBytes / 1024) KB.") }
            source.code = code
            source.style = nil
        } else if let style = args.optStr("style") {
            guard MusicStyle(rawValue: style) != nil else {
                throw MCPToolError("Unknown style '\(style)'. Use: \(MusicStyle.allCases.map(\.rawValue).joined(separator: ", ")), or pass 'code'.")
            }
            source.style = style
            source.code = nil
        }
        return source
    }

    /// Renders before the edit starts, so the open editor is not held while this runs.
    private func renderMusic(_ source: MusicSource, _ directory: URL) async throws -> (file: URL, seconds: TimeInterval) {
        let score: MusicScore
        if let name = source.style, let style = MusicStyle(rawValue: name) {
            score = .style(style)
        } else {
            score = .code(source.code ?? "")
        }
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let file = assets.appendingPathComponent(RenderedAssets.newFileName(.music))
        let seconds = try await MusicRenderer.render(score: score, to: file, options: source.options)
        do {
            try source.save(for: file)
        } catch {
            RenderedAssets.remove(file)
            throw error
        }
        return (file, seconds)
    }
}
