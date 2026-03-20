//
//  ProjectEditorPiPView.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit
import CoreGraphics

struct PiPConfigurationView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var cornerSnapshot: Project?

    var body: some View {
        if let camera = editor.project.canvas.layout.camera {
            let format = editor.project.canvas.format
            let aspectRatio = Double(format.w) / Double(format.h)

            VStack(alignment: .leading, spacing: 12) {
                PiPCanvasEditor(
                    editor: editor,
                    camera: camera,
                    aspectRatio: aspectRatio
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline)

                    HStack(spacing: 6) {
                        ForEach(PiPPreset.allCases, id: \.self) { preset in
                            Button(preset.rawValue) {
                                let updated = PiPLayoutHelper.presetPosition(preset, camera: camera)
                                Task {
                                    _ = await editor.updateCameraPosition(updated, recordUndoFrom: editor.project)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Corner Radius")
                        .font(.subheadline)

                    Slider(
                        value: Binding(
                            get: { camera.cornerRadius },
                            set: { newValue in
                                var updated = camera
                                updated.cornerRadius = newValue
                                Task {
                                    _ = await editor.updateCameraPosition(updated)
                                }
                            }
                        ),
                        in: 0...40,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                cornerSnapshot = editor.project
                            } else if let snapshot = cornerSnapshot,
                                      let currentCamera = editor.project.canvas.layout.camera {
                                Task {
                                    _ = await editor.updateCameraPosition(currentCamera, recordUndoFrom: snapshot)
                                }
                                cornerSnapshot = nil
                            }
                        }
                    )
                }
            }
        }
    }
}

struct PiPCanvasEditor: View {
    @ObservedObject var editor: ProjectEditor
    let camera: Project.Canvas.Layout.CameraPosition
    let aspectRatio: Double

    @State private var dragStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var dragSnapshot: Project?
    @State private var resizeStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var resizeSnapshot: Project?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = editor.project.canvas.layout
            let ekCameraFrame = CanvasLayout.calculateCameraFrame(
                layout: layout,
                canvasWidth: Int(size.width),
                canvasHeight: Int(size.height)
            )
            
            let cameraFrame = ekCameraFrame.map { ekFrame in
                CoreGraphics.CGRect(x: CGFloat(ekFrame.minX), y: CGFloat(ekFrame.minY), width: CGFloat(ekFrame.width), height: CGFloat(ekFrame.height))
            } ?? CoreGraphics.CGRect.zero

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .padding(6)

                RoundedRectangle(cornerRadius: max(2, camera.cornerRadius), style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: cameraFrame.width, height: cameraFrame.height)
                    .position(x: cameraFrame.midX, y: cameraFrame.midY)
                    .overlay(
                        RoundedRectangle(cornerRadius: max(2, camera.cornerRadius), style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .gesture(moveGesture(in: size))

                ForEach(PiPHandle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .position(handlePosition(handle, frame: cameraFrame))
                        .gesture(resizeGesture(for: handle, in: size))
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func handlePosition(_ handle: PiPHandle, frame: CoreGraphics.CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragStartCamera ?? camera
                if dragStartCamera == nil {
                    dragStartCamera = camera
                    dragSnapshot = editor.project
                }

                let updated = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                print("[PIP-DEBUG] Drag: x=\(updated.x), y=\(updated.y), w=\(updated.w), h=\(updated.h)")
                Task {
                    _ = await editor.updateCameraPosition(updated)
                }
            }
            .onEnded { value in
                let base = dragStartCamera ?? camera
                let updated = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                if let snapshot = dragSnapshot {
                    Task {
                        _ = await editor.updateCameraPosition(updated, recordUndoFrom: snapshot)
                    }
                }
                dragStartCamera = nil
                dragSnapshot = nil
            }
    }

    private func resizeGesture(for handle: PiPHandle, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = resizeStartCamera ?? camera
                if resizeStartCamera == nil {
                    resizeStartCamera = camera
                    resizeSnapshot = editor.project
                }

                let updated = PiPLayoutHelper.resized(
                    camera: base,
                    handle: handle,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                Task {
                    _ = await editor.updateCameraPosition(updated)
                }
            }
            .onEnded { value in
                let base = resizeStartCamera ?? camera
                let updated = PiPLayoutHelper.resized(
                    camera: base,
                    handle: handle,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                if let snapshot = resizeSnapshot {
                    Task {
                        _ = await editor.updateCameraPosition(updated, recordUndoFrom: snapshot)
                    }
                }
                resizeStartCamera = nil
                resizeSnapshot = nil
            }
    }
}
