//
//  ProjectEditor+Canvas.swift
//  App
//
//  Canvas configuration edits: layout preset, camera position, background
//  (type/color/image/fit), and output format. Extracted from
//  ProjectEditor.swift to keep it inside the 400-500 line budget; uses the
//  internal setEditorProject/recordUndo helpers.
//

import Foundation
import EngineKit

extension ProjectEditor {
    @discardableResult
    func setLayoutPreset(_ preset: CanvasLayout.LayoutPreset) async -> Bool {
        let hasCamera = project.primarySources?.camera != nil
        if preset != .fullscreen && !hasCamera { return false }
        return await applyCanvasUpdate {
            $0.canvas.layout = CanvasLayout.defaultLayout(for: preset)
            if !hasCamera { $0.canvas.layout.camera = nil }
            try CanvasLayout.validateLayout($0.canvas.layout, hasCamera: hasCamera)
        }
    }

    @discardableResult
    func updateCameraPosition(
        _ camera: Project.Canvas.Layout.CameraPosition,
        recordUndoFrom snapshot: Project? = nil
    ) async -> Bool {
        let hasCamera = project.primarySources?.camera != nil
        return await applyCanvasUpdate(saveAfter: true) {
            $0.canvas.layout.camera = camera
            try CanvasLayout.validateLayout($0.canvas.layout, hasCamera: hasCamera)
        }
    }

    @discardableResult
    func setBackgroundType(_ type: CanvasLayout.BackgroundType) async -> Bool {
        let currentFitMode = CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.defaultBackground(for: type, fitMode: currentFitMode)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundColor(_ hexColor: String) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createSolidBackground(hexColor: hexColor)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundImagePath(
        _ imagePath: String,
        fitMode: CanvasLayout.ImageFitMode? = nil
    ) async -> Bool {
        let resolvedFitMode = fitMode ?? CanvasLayout.ImageFitMode(
            rawValue: project.canvas.background.fitMode ?? CanvasLayout.ImageFitMode.fill.rawValue
        ) ?? .fill
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createImageBackground(imagePath: imagePath, fitMode: resolvedFitMode)
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackgroundFitMode(_ fitMode: CanvasLayout.ImageFitMode) async -> Bool {
        guard project.canvas.background.type == CanvasLayout.BackgroundType.image.rawValue else {
            return false
        }
        return await applyCanvasUpdate {
            $0.canvas.background = CanvasLayout.createImageBackground(
                imagePath: $0.canvas.background.value,
                fitMode: fitMode
            )
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func updateBackground(_ background: Project.Canvas.Background) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.background = background
            try CanvasLayout.validateBackground($0.canvas.background)
        }
    }

    @discardableResult
    func setFormat(_ aspectRatio: CanvasLayout.AspectRatio) async -> Bool {
        return await applyCanvasUpdate {
            $0.canvas.format = CanvasLayout.createFormat(for: aspectRatio)
            try CanvasLayout.validateFormat($0.canvas.format)
        }
    }

    @discardableResult
    private func applyCanvasUpdate(
        saveAfter: Bool = false,
        _ mutation: (inout Project) throws -> Void
    ) async -> Bool {
        let previousProject = project
        var updatedProject = project
        do { try mutation(&updatedProject) } catch { return false }
        await setEditorProject(updatedProject)
        project = updatedProject
        recordUndo(previousProject)
        if saveAfter { scheduleAutosave() }
        return true
    }
}
