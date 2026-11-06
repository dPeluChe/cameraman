//
//  MCPTools+Motion.swift
//  cameraman-mcp
//
//  add_motion, update_motion: render a motion graphic (a template or custom HTML) to a transparent video and
//  place it over the footage as a clip. Rendering needs a window server, so it only runs when the
//  app hosts the server.
//

import Foundation
import EngineKit

extension MCPTools {

    static let maxMotionHTMLBytes = 512 * 1024

    func addMotion(_ args: [String: Any]) async throws -> String {
        let at = try args.num("at")
        guard at >= 0 else { throw MCPToolError("'at' must be 0 or later.") }
        let source = try Self.motionSource(args, editing: nil)
        let position = try Self.placement(args)
        let project = try await loadProject(args)
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let (file, rendered) = try await renderMotion(source, project, directory)

        return try await RenderedAssets.removing(file) {
            let path = RenderedAssets.projectPath(of: file)
            var added: EditorResultInfo?
            let updated = try await mutate(args) { editor in
                let track = await editor.freeTrack(.video, named: MotionSource.trackName, from: at, to: at + rendered.duration)
                let result = await editor.importVideoClip(path: path, duration: rendered.duration, at: at, trackName: MotionSource.trackName,
                                                          position: position, belowCamera: true, onTrack: track)
                if case .successWithInfo(_, let info) = result { added = info }
                return result
            }
            let extra = await visibleArea(of: file, at: position, in: updated).merging(Self.clipIds(added)) { $1 }
            return try summary("Added motion (\(rendered.frameCount) frames, \(String(format: "%.1f", rendered.duration))s) at \(at)s", updated, extra: extra)
        }
    }

    func updateMotion(_ args: [String: Any]) async throws -> String {
        let (project, track, clip) = try await resolveClip(args)
        guard let path = RenderedAssets.renderedPath(of: clip, as: .motion) else {
            throw MCPToolError("That clip is not a motion.")
        }
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: project.projectId)
        let saved = MotionSource.load(for: directory.appendingPathComponent(path))
        guard saved != nil || args.optStr("html") != nil || args.optStr("template") != nil else {
            throw MCPToolError("This motion was made before they could be edited. Pass its full 'html' or a 'template'.")
        }
        let source = try Self.motionSource(args, editing: saved)
        let (file, rendered) = try await renderMotion(source, project, directory)

        return try await RenderedAssets.removing(file) {
            let content = Project.ClipContent.video(Project.VideoClipRef(path: RenderedAssets.projectPath(of: file), sourceOut: rendered.duration))
            let updated = try await mutate(args) { await $0.replaceClipContent(clipId: clip.id, inTrackId: track.id, content: content) }
            // The old video stays for undo; RenderedAssets removes it when the project next opens.
            let extra = await visibleArea(of: file, at: clip.position, in: updated)
            return try summary("Updated motion \(clip.id)", updated, extra: extra)
        }
    }

    /// The new source: `args` over what was saved, keeping only the fields that were not passed.
    static func motionSource(_ args: [String: Any], editing saved: MotionSource?) throws -> MotionSource {
        var source = saved ?? MotionSource()
        if let requested = args.optNum("duration") {
            guard (0.5...120).contains(requested) else { throw MCPToolError("'duration' must be between 0.5 and 120 seconds.") }
            source.duration = requested
        }
        if let title = args.optStr("title") { source.title = title }
        if let subtitle = args.optStr("subtitle") { source.subtitle = subtitle }
        if let value = args.optStr("value") { source.value = value }
        if let labels = args.optStrArray("labels") { source.labels = labels }
        if let values = args["values"] as? [Any] {
            source.values = values.compactMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) }
        }
        if let color = args.optStr("color") { source.colorHex = color }

        if let custom = args.optStr("html") {
            guard args.optStr("template") == nil else { throw MCPToolError("Pass either 'template' or 'html', not both.") }
            guard custom.utf8.count <= Self.maxMotionHTMLBytes else {
                throw MCPToolError("'html' is larger than \(Self.maxMotionHTMLBytes / 1024) KB.")
            }
            source.html = custom
            source.template = nil
        } else if let name = args.optStr("template") {
            source.template = name
            source.html = nil
        }
        return source
    }

    static func motionPage(_ source: MotionSource) throws -> (html: String, duration: TimeInterval?) {
        if let html = source.html { return (html, source.duration) }
        guard let name = source.template else { throw MCPToolError("Pass 'template' or 'html'.") }
        guard let template = MotionTemplate(rawValue: name) else {
            throw MCPToolError("Unknown template '\(name)'. Use: \(MotionTemplate.allCases.map(\.rawValue).joined(separator: ", ")), or pass 'html'.")
        }
        let content = MotionTemplate.Content(title: source.title, subtitle: source.subtitle, value: source.value,
                                             labels: source.labels, values: source.values, colorHex: source.colorHex)
        return (try template.html(content, duration: source.duration ?? MotionTemplate.defaultDuration), nil)
    }

    /// Renders before the edit starts, so the open editor is not held while this runs.
    private func renderMotion(_ source: MotionSource, _ project: Project,
                              _ directory: URL) async throws -> (file: URL, output: MotionRenderResult) {
        let page = try Self.motionPage(source)
        let size = Self.motionSize(for: project.canvas.format)
        return try await RenderedAssets.render(source, in: directory) { file in
            try await MotionRenderer.render(
                html: page.html, to: file,
                options: MotionRenderOptions(width: size.width, height: size.height, fps: 30, duration: page.duration))
        }
    }

    private func visibleArea(of file: URL, at position: Project.MediaPosition?, in project: Project) async -> [String: Any] {
        guard let shape = await VideoContentShape.measure(url: file) else { return [:] }
        let canvas = CGSize(width: project.canvas.format.w, height: project.canvas.format.h)
        return ["visibleArea": Self.area(shape.visibleArea(at: position ?? Project.MediaPosition(), canvas: canvas))]
    }


    /// The canvas size capped at 1440p, even sides: lower looks soft on wide captures.
    static func motionSize(for format: Project.Canvas.Format) -> (width: Int, height: Int) {
        let w = max(format.w, 2), h = max(format.h, 2)
        let scale = min(1, 2560.0 / Double(max(w, h)), 1440.0 / Double(min(w, h)))
        return (max(2, Int(Double(w) * scale) / 2 * 2), max(2, Int(Double(h) * scale) / 2 * 2))
    }
}
