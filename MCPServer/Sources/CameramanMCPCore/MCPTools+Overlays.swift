//
//  MCPTools+Overlays.swift
//  cameraman-mcp
//
//  Symmetric overlay editing via OverlayEngine: add arrow/rect/line/text (with
//  optional draw-on / fade-in animation), list, update (partial), and delete.
//  Complements the existing add_text_overlay tool.
//

import Foundation
import EngineKit

extension MCPTools {

    func addOverlay(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let typeRaw = try args.str("type")
        guard let type = Project.Overlay.OverlayType(rawValue: typeRaw),
              [.arrow, .rect, .line, .text].contains(type) else {
            throw MCPToolError("Unknown overlay type '\(typeRaw)'. Use: arrow, rect, line, text.")
        }
        let start = try args.num("start")
        let end = try args.num("end")
        let x = args.optNum("x") ?? 0.5
        let y = args.optNum("y") ?? 0.5
        let scale = args.optNum("scale") ?? 1.0
        let rotation = args.optNum("rotation") ?? 0.0
        let stroke = args.optStr("stroke") ?? "#FFFFFF"
        let strokeWidth = args.optNum("strokeWidth")
        let drawOn = args.optBool("drawOn") ?? false

        let result: OverlayResult
        switch type {
        case .arrow:
            result = drawOn
                ? try await overlayEngine.addArrowOverlayWithDrawOn(projectId: projectId, start: start, end: end, x: x, y: y, scale: scale, rotation: rotation, stroke: stroke, strokeWidth: strokeWidth ?? 6.0)
                : try await overlayEngine.addArrowOverlay(projectId: projectId, start: start, end: end, x: x, y: y, scale: scale, rotation: rotation, stroke: stroke, strokeWidth: strokeWidth ?? 6.0)
        case .line:
            result = drawOn
                ? try await overlayEngine.addLineOverlayWithDrawOn(projectId: projectId, start: start, end: end, x: x, y: y, scale: scale, rotation: rotation, stroke: stroke, strokeWidth: strokeWidth ?? 4.0)
                : try await overlayEngine.addLineOverlay(projectId: projectId, start: start, end: end, x: x, y: y, scale: scale, rotation: rotation, stroke: stroke, strokeWidth: strokeWidth ?? 4.0)
        case .rect:
            result = try await overlayEngine.addRectOverlay(projectId: projectId, start: start, end: end, x: x, y: y, scale: scale, rotation: rotation, stroke: stroke, strokeWidth: strokeWidth ?? 4.0)
        case .text:
            let text = try args.str("text")
            let size = args.optNum("fontSize") ?? 36.0
            let color = args.optStr("color") ?? "#FFFFFF"
            let fadeIn = args.optBool("fadeIn") ?? false
            result = fadeIn
                ? try await overlayEngine.addTextOverlayWithFadeIn(projectId: projectId, start: start, end: end, x: x, y: y, text: text, scale: scale, rotation: rotation, size: size, color: color)
                : try await overlayEngine.addTextOverlay(projectId: projectId, start: start, end: end, x: x, y: y, text: text, scale: scale, rotation: rotation, size: size, color: color)
        default:
            throw MCPToolError("Unsupported overlay type '\(typeRaw)'.")
        }
        let id = try Self.overlayId(from: result)
        return try json(["overlayId": id.uuidString, "type": typeRaw,
                         "message": "Added \(typeRaw) overlay [\(start)s–\(end)s]. Manage it with update_overlay / delete_overlay."])
    }

    func listOverlays(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let overlays = try await overlayEngine.getOverlays(projectId: projectId)
        return try jsonText(overlays)
    }

    func updateOverlay(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let overlayId = try args.uuid("overlayId")
        let existing = try await overlayEngine.getOverlay(projectId: projectId, overlayId: overlayId)

        // Build a merged transform only if any transform field was supplied.
        var transform: Project.Overlay.Transform?
        if args["x"] != nil || args["y"] != nil || args["scale"] != nil || args["rotation"] != nil {
            transform = Project.Overlay.Transform(
                x: args.optNum("x") ?? existing.transform.x,
                y: args.optNum("y") ?? existing.transform.y,
                scale: args.optNum("scale") ?? existing.transform.scale,
                rotation: args.optNum("rotation") ?? existing.transform.rotation
            )
        }

        // Merge style only if any style field was supplied.
        var style: Project.Overlay.Style?
        if args["stroke"] != nil || args["strokeWidth"] != nil || args["color"] != nil
            || args["fontSize"] != nil || args["text"] != nil {
            var s = existing.style
            if let v = args.optStr("stroke") { s.stroke = v }
            if let v = args.optNum("strokeWidth") { s.strokeWidth = v }
            if let v = args.optStr("color") { s.color = v }
            if let v = args.optNum("fontSize") { s.size = v }
            if let v = args.optStr("text") { s.text = v }
            style = s
        }

        let result = try await overlayEngine.updateOverlay(
            projectId: projectId, overlayId: overlayId,
            start: args.optNum("start"), end: args.optNum("end"),
            transform: transform, style: style
        )
        _ = try Self.overlayId(from: result)
        return "Updated overlay \(overlayId)"
    }

    func deleteOverlay(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let overlayId = try args.uuid("overlayId")
        let result = try await overlayEngine.deleteOverlay(projectId: projectId, overlayId: overlayId)
        _ = try Self.overlayId(from: result)
        return "Deleted overlay \(overlayId)"
    }

    private static func overlayId(from result: OverlayResult) throws -> UUID {
        switch result {
        case .success(let id): return id
        case .failure(let error): throw MCPToolError("Overlay operation failed: \(error)")
        }
    }
}
