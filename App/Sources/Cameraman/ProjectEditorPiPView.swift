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
    var selectedSegmentId: String? = nil
    var playerViewModel: PreviewPlayerViewModel? = nil
    @State private var cornerSnapshot: Project?
    private let presetColumns = [GridItem(.adaptive(minimum: 52, maximum: 82), spacing: 6)]
    private let shapeColumns = [GridItem(.adaptive(minimum: 44, maximum: 58), spacing: 6)]

    /// Whether we're editing a segment's camera override vs project camera
    private var isEditingSegment: Bool {
        guard let segId = selectedSegmentId else { return false }
        return editor.project.timeline.segments.first(where: { $0.id == segId })?.cameraPosition != nil
    }

    /// The active camera to display/edit
    private var activeCamera: Project.Canvas.Layout.CameraPosition? {
        if let segId = selectedSegmentId,
           let segCam = editor.project.timeline.segments.first(where: { $0.id == segId })?.cameraPosition {
            return segCam
        }
        return editor.project.canvas.layout.camera
    }

    /// Unified update: routes to segment or project camera
    private func updateCamera(_ camera: Project.Canvas.Layout.CameraPosition, recordUndo: Bool = false) {
        Task {
            if let segId = selectedSegmentId {
                _ = await editor.updateSegmentCameraPosition(segmentId: segId, camera: camera)
            } else if recordUndo {
                _ = await editor.updateCameraPosition(camera, recordUndoFrom: editor.project)
            } else {
                _ = await editor.updateCameraPosition(camera)
            }
        }
    }

    var body: some View {
        if let camera = activeCamera {
            let format = editor.project.canvas.format
            let aspectRatio = Double(format.w) / Double(format.h)

            VStack(alignment: .leading, spacing: 12) {
                if selectedSegmentId != nil {
                    HStack {
                        Image(systemName: "camera.circle.fill")
                            .foregroundStyle(isEditingSegment ? .green : .orange)
                        Text(isEditingSegment ? "Segment camera (custom)" : "Segment camera (drag to customize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PiPCanvasEditor(
                    editor: editor,
                    camera: camera,
                    aspectRatio: aspectRatio,
                    selectedSegmentId: selectedSegmentId,
                    playerViewModel: playerViewModel
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline)

                    LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 6) {
                        ForEach(PiPPreset.allCases, id: \.self) { preset in
                            Button(preset.rawValue) {
                                let updated = PiPLayoutHelper.presetPosition(preset, camera: camera)
                                updateCamera(updated, recordUndo: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shape")
                        .font(.subheadline)

                    LazyVGrid(columns: shapeColumns, alignment: .leading, spacing: 6) {
                        ForEach(PiPMaskShape.allCases, id: \.self) { shape in
                            let isSelected = camera.maskShape == shape
                            Button {
                                var updated = camera
                                updated.maskShape = shape
                                updateCamera(updated, recordUndo: true)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: shapeIcon(shape))
                                        .font(.system(size: 12))
                                    Text(shapeLabel(shape))
                                        .font(.system(size: 8))
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                                updateCamera(updated)
                            }
                        ),
                        in: 0...40,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                cornerSnapshot = editor.project
                            } else if let currentCamera = activeCamera {
                                if let snapshot = cornerSnapshot {
                                    if isEditingSegment, let segId = selectedSegmentId {
                                        Task { _ = await editor.updateSegmentCameraPosition(segmentId: segId, camera: currentCamera) }
                                    } else {
                                        Task { _ = await editor.updateCameraPosition(currentCamera, recordUndoFrom: snapshot) }
                                    }
                                }
                                cornerSnapshot = nil
                            }
                        }
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Border")
                            .font(.subheadline)
                        Spacer()
                        Text(camera.borderWidth > 0 ? "\(Int(camera.borderWidth))px" : "Off")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { camera.borderWidth },
                            set: { newValue in
                                var updated = camera
                                updated.borderWidth = newValue
                                updateCamera(updated)
                            }
                        ),
                        in: 0...8,
                        step: 0.5
                    )
                    .controlSize(.small)

                    if camera.borderWidth > 0 {
                        HStack(spacing: 6) {
                            ForEach(borderColorPresets, id: \.self) { hex in
                                let isSelected = camera.borderColor == hex
                                Button {
                                    var updated = camera
                                    updated.borderColor = hex
                                    updateCamera(updated, recordUndo: true)
                                } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private let borderColorPresets: [String] = [
        "#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55"
    ]

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
    var selectedSegmentId: String? = nil
    var playerViewModel: PreviewPlayerViewModel? = nil

    @State private var dragStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var dragSnapshot: Project?
    @State private var resizeStartCamera: Project.Canvas.Layout.CameraPosition?
    @State private var resizeSnapshot: Project?
    /// Last time we pushed a camera draft to the engine. DragGesture fires at
    /// 60–120 Hz on ProMotion, but the AVPlayer doesn't benefit from updates
    /// faster than the display refresh, and each call rebuilds the
    /// videoComposition. Throttling to ~33ms (≈30Hz) is visually smooth and
    /// halves the work.
    @State private var lastDraftPush: Date = .distantPast
    private static let draftThrottle: TimeInterval = 1.0 / 30.0
    /// Live preview of the camera during an active drag/resize. While non-nil,
    /// the canvas renders from this instead of the committed `camera` prop —
    /// the project (and AVPlayer rebuild) is only updated on gesture end.
    /// Without this, every drag tick republished `editor.project`, debounced
    /// to `PreviewPlayerView.onReceive`, rebuilding the composition + swapping
    /// the AVPlayer mid-playback. The visible symptom was "drag doesn't work
    /// while playing, only when paused".
    @State private var draftCamera: Project.Canvas.Layout.CameraPosition?

    /// Camera used for rendering — draft takes precedence during gesture.
    private var displayCamera: Project.Canvas.Layout.CameraPosition {
        draftCamera ?? camera
    }

    private var isEditingSegment: Bool {
        guard let segId = selectedSegmentId else { return false }
        return editor.project.timeline.segments.first(where: { $0.id == segId })?.cameraPosition != nil
    }

    private func commitCamera(_ cam: Project.Canvas.Layout.CameraPosition, recordUndo: Bool = false, from snapshot: Project? = nil) {
        Task {
            if let segId = selectedSegmentId {
                // Auto-create per-segment override when dragging with segment selected
                _ = await editor.updateSegmentCameraPosition(segmentId: segId, camera: cam)
            } else if recordUndo, let snapshot {
                _ = await editor.updateCameraPosition(cam, recordUndoFrom: snapshot)
            } else {
                _ = await editor.updateCameraPosition(cam)
            }
        }
    }

    /// Push the draft to the engine, throttled to ~30Hz to avoid rebuilding the
    /// videoComposition on every gesture tick (DragGesture can fire at 120Hz
    /// on ProMotion displays).
    private func pushDraftIfNeeded(_ camera: Project.Canvas.Layout.CameraPosition) {
        let now = Date()
        guard now.timeIntervalSince(lastDraftPush) >= Self.draftThrottle else { return }
        lastDraftPush = now
        playerViewModel?.previewCameraDraft(camera, segmentId: selectedSegmentId)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let render = displayCamera
            // Use the camera prop (segment-aware) to calculate frame, not project layout
            let cameraFrame = CoreGraphics.CGRect(
                x: CGFloat(render.x) * size.width,
                y: CGFloat(render.y) * size.height,
                width: CGFloat(render.w) * size.width,
                height: CGFloat(render.h) * size.height
            )

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
        CameraPreviewShape(maskShape: displayCamera.maskShape, cornerRadius: displayCamera.cornerRadius)
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
                if dragStartCamera == nil {
                    dragStartCamera = camera
                    dragSnapshot = editor.project
                }
                let base = dragStartCamera ?? camera
                let next = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                draftCamera = next
                // Live preview: push the draft directly to the engine so the
                // AVPlayer reflects the new position without waiting for the
                // gesture to end (editor.project publish + 150ms debounce).
                pushDraftIfNeeded(next)
            }
            .onEnded { value in
                let base = dragStartCamera ?? camera
                let updated = PiPLayoutHelper.moved(
                    camera: base,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                // Commit once at gesture end — single project update + single
                // preview rebuild, instead of one per drag tick.
                if let snapshot = dragSnapshot {
                    commitCamera(updated, recordUndo: true, from: snapshot)
                }
                dragStartCamera = nil
                dragSnapshot = nil
                draftCamera = nil
            }
    }

    private func resizeGesture(for handle: PiPHandle, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStartCamera == nil {
                    resizeStartCamera = camera
                    resizeSnapshot = editor.project
                }
                let base = resizeStartCamera ?? camera
                let next = PiPLayoutHelper.resized(
                    camera: base,
                    handle: handle,
                    deltaX: Double(value.translation.width / size.width),
                    deltaY: Double(value.translation.height / size.height)
                )
                draftCamera = next
                pushDraftIfNeeded(next)
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
                    commitCamera(updated, recordUndo: true, from: snapshot)
                }
                resizeStartCamera = nil
                resizeSnapshot = nil
                draftCamera = nil
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
