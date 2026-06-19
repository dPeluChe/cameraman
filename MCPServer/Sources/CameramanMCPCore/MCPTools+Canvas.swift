//
//  MCPTools+Canvas.swift
//  cameraman-mcp
//
//  Canvas composition: layout (fullscreen / pip / side-by-side, plus the camera
//  PiP placement) and background (color / image / blur). Canvas is plain project
//  metadata, so these load the project, mutate `project.canvas`, and persist —
//  no EditorModel round-trip needed.
//

import Foundation
import EngineKit

extension MCPTools {

    func setCanvasLayout(_ args: [String: Any]) async throws -> String {
        var project = try await loadProject(args)

        if let typeRaw = args.optStr("type") {
            let valid = ["fullscreen", "pip", "side_by_side"]
            guard valid.contains(typeRaw) else {
                throw MCPToolError("Unknown layout '\(typeRaw)'. Use: \(valid.joined(separator: ", ")).")
            }
            let camera: Project.Canvas.Layout.CameraPosition?
            if typeRaw == "fullscreen" {
                camera = nil
            } else if let cameraArg = args["camera"] as? [String: Any] {
                camera = Self.cameraPosition(from: cameraArg)
            } else {
                // Keep an existing camera, or default to a bottom-right PiP.
                camera = project.canvas.layout.camera
                    ?? Project.Canvas.Layout.CameraPosition(x: 0.68, y: 0.68, w: 0.3, h: 0.3)
            }
            project.canvas.layout = Project.Canvas.Layout(type: typeRaw, camera: camera)
        }

        if let padding = args.optNum("padding") {
            project.canvas.padding = min(max(padding, 0), 0.3)
        }
        if let radius = args.optNum("videoCornerRadius") {
            project.canvas.videoCornerRadius = max(0, radius)
        }
        if let shadow = args.optNum("videoShadowIntensity") {
            project.canvas.videoShadowIntensity = min(max(shadow, 0), 1)
        }

        try await ProjectLibrary.shared.updateProject(project)
        return try summary("Updated canvas layout (\(project.canvas.layout.type))", project)
    }

    func setBackground(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let type = try args.str("type")
        let valid = ["color", "image", "blur"]
        guard valid.contains(type) else {
            throw MCPToolError("Unknown background type '\(type)'. Use: \(valid.joined(separator: ", ")).")
        }
        let value = try args.str("value")
        let fitMode = args.optStr("fitMode")

        var project = try await loadProject(args)
        // For an image background, copy the source into the project's assets/.
        var resolvedValue = value
        if type == "image" {
            let dir = try await ProjectLibrary.shared.getProjectDirectory(projectId: projectId)
            resolvedValue = try ProjectLibrary.stageAsset(
                from: URL(fileURLWithPath: value), intoProjectDirectory: dir
            )
        }
        project.canvas.background = Project.Canvas.Background(
            type: type, value: resolvedValue, fitMode: fitMode
        )
        try await ProjectLibrary.shared.updateProject(project)
        return try summary("Updated background (\(type))", project)
    }

    private static func cameraPosition(from dict: [String: Any]) -> Project.Canvas.Layout.CameraPosition {
        func num(_ key: String, _ fallback: Double) -> Double {
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return fallback
        }
        let maskShape = (dict["maskShape"] as? String).flatMap(PiPMaskShape.init(rawValue:)) ?? .roundedRect
        return Project.Canvas.Layout.CameraPosition(
            x: num("x", 0.68),
            y: num("y", 0.68),
            w: num("w", 0.3),
            h: num("h", 0.3),
            cornerRadius: num("cornerRadius", 0),
            maskShape: maskShape,
            borderWidth: num("borderWidth", 0),
            borderColor: (dict["borderColor"] as? String) ?? "#FFFFFF"
        )
    }
}
