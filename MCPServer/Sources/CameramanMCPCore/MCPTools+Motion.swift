//
//  MCPTools+Motion.swift
//  cameraman-mcp
//
//  add_motion: render a motion graphic (a template or custom HTML) to a transparent video and
//  place it over the footage as a clip. Rendering needs a window server, so it only runs when the
//  app hosts the server.
//

import Foundation
import EngineKit

extension MCPTools {

    static let maxMotionHTMLBytes = 512 * 1024

    func addMotion(_ args: [String: Any]) async throws -> String {
        guard supportsMotion else {
            throw MCPToolError("add_motion renders inside the Cameraman app. Turn on the MCP server in the app (Preferences > Integrations) and connect to that one; the standalone cameraman-mcp binary cannot render motion.")
        }
        let projectId = try args.uuid("projectId")
        let at = try args.num("at")
        guard at >= 0 else { throw MCPToolError("'at' must be 0 or later.") }
        let requested = args.optNum("duration")
        if let requested, !(0.5...120).contains(requested) { throw MCPToolError("'duration' must be between 0.5 and 120 seconds.") }

        let html: String
        var overrideDuration: TimeInterval?
        if let custom = args.optStr("html") {
            guard args.optStr("template") == nil else { throw MCPToolError("Pass either 'template' or 'html', not both.") }
            guard custom.utf8.count <= Self.maxMotionHTMLBytes else { throw MCPToolError("'html' is larger than \(Self.maxMotionHTMLBytes / 1024) KB.") }
            html = custom
            overrideDuration = requested
        } else {
            let name = try args.str("template")
            guard let template = MotionTemplate(rawValue: name) else {
                throw MCPToolError("Unknown template '\(name)'. Use: \(MotionTemplate.allCases.map(\.rawValue).joined(separator: ", ")), or pass 'html'.")
            }
            let content = MotionTemplate.Content(
                title: args.optStr("title") ?? "", subtitle: args.optStr("subtitle") ?? "", value: args.optStr("value") ?? "",
                labels: args.optStrArray("labels") ?? [],
                values: (args["values"] as? [Any])?.compactMap { ($0 as? Double) ?? ($0 as? Int).map(Double.init) } ?? [],
                colorHex: args.optStr("color") ?? "#0A84FF")
            html = try template.html(content, duration: requested ?? MotionTemplate.defaultDuration)
        }

        var position: Project.MediaPosition?
        let placement = ["x", "y", "w", "h"].map { args.optNum($0) }
        if placement.contains(where: { $0 != nil }) {
            guard let x = placement[0], let y = placement[1], let w = placement[2], let h = placement[3] else {
                throw MCPToolError("To place the motion pass x, y, w and h together (0-1 fractions of the canvas), or none for full screen.")
            }
            position = Project.MediaPosition(x: x, y: y, w: w, h: h)
        }

        let project = try await loadProject(args)
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: projectId)
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let filename = "motion-\(UUID().uuidString.prefix(8).lowercased()).mov"
        let file = assets.appendingPathComponent(filename)

        // Rendered before the edit starts, so the open editor is not held while this runs.
        let size = Self.motionSize(for: project.canvas.format)
        let rendered = try await MotionRenderer.render(
            html: html, to: file,
            options: MotionRenderOptions(width: size.width, height: size.height, fps: 30, duration: overrideDuration))

        do {
            let updated = try await mutate(args) {
                await $0.importVideoClip(path: "assets/\(filename)", duration: rendered.duration, at: at,
                                         trackName: "Motion", position: position, belowCamera: true)
            }
            return try summary("Added motion (\(rendered.frameCount) frames, \(String(format: "%.1f", rendered.duration))s) at \(at)s", updated)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// The canvas size capped at 1080p, even sides.
    static func motionSize(for format: Project.Canvas.Format) -> (width: Int, height: Int) {
        let w = max(format.w, 2), h = max(format.h, 2)
        let scale = min(1, 1920.0 / Double(w), 1920.0 / Double(h), 1080.0 / Double(min(w, h)))
        return (max(2, Int(Double(w) * scale) / 2 * 2), max(2, Int(Double(h) * scale) / 2 * 2))
    }
}
