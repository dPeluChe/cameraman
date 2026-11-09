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
        var project = try await loadForEdit(args)

        if let typeRaw = args.optStr("type") {
            let valid = ["fullscreen", "pip", "side_by_side"]
            guard valid.contains(typeRaw) else {
                throw MCPToolError("Unknown layout '\(typeRaw)'. Use: \(valid.joined(separator: ", ")).")
            }
            let camera: Project.Canvas.Layout.CameraPosition?
            if typeRaw == "fullscreen" {
                camera = nil
            } else if let cameraArg = args["camera"] as? [String: Any] {
                camera = Self.cameraPosition(from: cameraArg, keeping: project.canvas.layout.camera)
            } else if typeRaw == "side_by_side" {
                camera = CanvasLayout.defaultLayout(for: .sideBySide).camera
            } else {
                // Keep an existing camera, or default to a bottom-right PiP.
                camera = project.canvas.layout.camera
                    ?? Project.Canvas.Layout.CameraPosition(x: 0.68, y: 0.68, w: 0.3, h: 0.3)
            }
            project.canvas.layout = Project.Canvas.Layout(type: typeRaw, camera: camera)
        }

        if let side = args.optStr("cameraSide") {
            guard project.canvas.layout.isSideBySide, ["left", "right"].contains(side) else {
                throw MCPToolError("cameraSide is left or right, and only applies to side_by_side.")
            }
            project.canvas.layout = project.canvas.layout.placingCamera(onLeft: side == "left")
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

        try await persist(project)
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

        var project = try await loadForEdit(args)
        // For an image background, copy the source into the project's assets/.
        var resolvedValue = value
        if type == "image" {
            resolvedValue = try await stageAsset(value, projectId: projectId)
        }
        project.canvas.background = Project.Canvas.Background(
            type: type, value: resolvedValue, fitMode: fitMode
        )
        try await persist(project)
        return try summary("Updated background (\(type))", project)
    }

    /// Fields left out keep `base`, so moving or resizing the camera does not drop its mask or border.
    static func cameraPosition(from dict: [String: Any], keeping base: Project.Canvas.Layout.CameraPosition?) -> Project.Canvas.Layout.CameraPosition {
        let base = base ?? Project.Canvas.Layout.CameraPosition(x: 0.68, y: 0.68, w: 0.3, h: 0.3)
        func num(_ key: String, _ fallback: Double) -> Double {
            (dict[key] as? Double) ?? (dict[key] as? Int).map(Double.init) ?? fallback
        }
        return Project.Canvas.Layout.CameraPosition(
            x: num("x", base.x),
            y: num("y", base.y),
            w: num("w", base.w),
            h: num("h", base.h),
            cornerRadius: num("cornerRadius", base.cornerRadius),
            maskShape: (dict["maskShape"] as? String).flatMap(PiPMaskShape.init(rawValue:)) ?? base.maskShape,
            borderWidth: num("borderWidth", base.borderWidth),
            borderColor: (dict["borderColor"] as? String) ?? base.borderColor
        )
    }
}
