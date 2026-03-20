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
                    Text("Shape")
                        .font(.subheadline)

                    HStack(spacing: 3) {
                        ForEach(PiPMaskShape.allCases, id: \.self) { shape in
                            let isSelected = camera.maskShape == shape
                            Button {
                                var updated = camera
                                updated.maskShape = shape
                                Task {
                                    _ = await editor.updateCameraPosition(updated, recordUndoFrom: editor.project)
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: shapeIcon(shape))
                                        .font(.system(size: 12))
                                    Text(shapeLabel(shape))
                                        .font(.system(size: 8))
                                }
                                .frame(width: 44, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
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

    private func shapeIcon(_ shape: PiPMaskShape) -> String {
        switch shape {
        case .none: return "rectangle"
        case .circle: return "circle"
        case .roundedRect: return "squareshape"
        case .capsule: return "capsule"
        }
    }

    private func shapeLabel(_ shape: PiPMaskShape) -> String {
        switch shape {
        case .none: return "Rect"
        case .circle: return "Circle"
        case .roundedRect: return "Round"
        case .capsule: return "Pill"
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

                cameraShapeView(frame: cameraFrame)
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

    @ViewBuilder
    private func cameraShapeView(frame: CoreGraphics.CGRect) -> some View {
        let shape = cameraShape
        shape
            .fill(Color.accentColor.opacity(0.6))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            )
    }

    private var cameraShape: some Shape {
        CameraPreviewShape(maskShape: camera.maskShape, cornerRadius: camera.cornerRadius)
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

// MARK: - Camera Preview Shape

struct CameraPreviewShape: Shape {
    let maskShape: PiPMaskShape
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        switch maskShape {
        case .none:
            return Path(rect)
        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            return Path(ellipseIn: circleRect)
        case .roundedRect:
            let radius = min(CGFloat(cornerRadius), min(rect.width, rect.height) / 2)
            return Path(roundedRect: rect, cornerRadius: radius)
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            return Path(roundedRect: rect, cornerRadius: radius)
        }
    }
}

