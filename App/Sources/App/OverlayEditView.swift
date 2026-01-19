//
//  OverlayEditView.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import SwiftUI

/// View for editing overlays with drag, resize, and style inspector
public struct OverlayEditView: View {
    @ObservedObject var projectEditor: ProjectEditor
    @Binding var currentTime: TimeInterval

    @State private var selectedOverlayId: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var resizeHandle: ResizeHandle?
    @State private var initialTransform: Project.Overlay.Transform?
    @State private var initialSize: CGSize?

    @State private var showStyleInspector: Bool = false

    private let canvasWidth: Double = 1920
    private let canvasHeight: Double = 1080

    public enum ResizeHandle {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    public init(projectEditor: ProjectEditor, currentTime: Binding<TimeInterval>) {
        self.projectEditor = projectEditor
        self._currentTime = currentTime
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Canvas area with overlays
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(hex: projectEditor.project.canvas.background.value))

                // Overlays
                ForEach(visibleOverlays) { overlay in
                    overlayView(for: overlay)
                }
            }
            .frameaspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )

            Divider()

            // Style inspector (shown when overlay is selected)
            if let selectedId = selectedOverlayId,
               let overlay = projectEditor.project.overlays.first(where: { $0.id == selectedId }) {
                StyleInspectorView(
                    overlay: overlay,
                    projectEditor: projectEditor,
                    isVisible: $showStyleInspector
                )
                .transition(.move(edge: .bottom))
            }
        }
    }

    /// Get overlays visible at current time
    private var visibleOverlays: [Project.Overlay] {
        projectEditor.project.overlays.filter { overlay in
            overlay.start <= currentTime && overlay.end >= currentTime
        }
    }

    /// View for a single overlay
    @ViewBuilder
    private func overlayView(for overlay: Project.Overlay) -> some View {
        let isSelected = selectedOverlayId == overlay.id
        let position = overlayPosition(for: overlay)
        let size = overlaySize(for: overlay)

        ZStack {
            // Overlay content
            overlayContent(for: overlay)
                .frame(width: size.width, height: size.height)
                .overlay(
                    // Selection border
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                                .frame(width: size.width + 4, height: size.height + 4)
                        }
                    }
                )
                .overlay(
                    // Resize handles (shown when selected)
                    Group {
                        if isSelected {
                            resizeHandle(at: .topLeft, size: size)
                            resizeHandle(at: .topRight, size: size)
                            resizeHandle(at: .bottomLeft, size: size)
                            resizeHandle(at: .bottomRight, size: size)
                        }
                    }
                )
        }
        .position(x: position.x, y: position.y)
        .onTapGesture {
            selectOverlay(overlay.id)
        }
        .gesture(
            DragGesture(coordinateSpace: .local)
                .onChanged { value in
                    if isSelected {
                        handleOverlayDragChanged(value, for: overlay)
                    }
                }
                .onEnded { value in
                    if isSelected {
                        handleOverlayDragEnded(value, for: overlay)
                    }
                }
        )
    }

    /// Overlay content based on type
    @ViewBuilder
    private func overlayContent(for overlay: Project.Overlay) -> some View {
        switch overlay.type {
        case .arrow:
            arrowShape(for: overlay)
                .stroke(Color(hex: overlay.style.stroke), lineWidth: overlay.style.strokeWidth)
                .shadow(color: overlay.style.shadow ? Color.black.opacity(0.5) : .clear, radius: 4)
                .frame(width: 100, height: 100)

        case .rect:
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: overlay.style.stroke), lineWidth: overlay.style.strokeWidth)
                .shadow(color: overlay.style.shadow ? Color.black.opacity(0.5) : .clear, radius: 4)
                .frame(width: 150, height: 100)

        case .line:
            LineShape()
                .stroke(Color(hex: overlay.style.stroke), lineWidth: overlay.style.strokeWidth)
                .shadow(color: overlay.style.shadow ? Color.black.opacity(0.5) : .clear, radius: 4)
                .frame(width: 150, height: 4)

        case .text:
            if let text = overlay.style.text {
                Text(text)
                    .font(.custom(overlay.style.font ?? "SF Pro", size: overlay.style.size ?? 36))
                    .foregroundColor(Color(hex: overlay.style.color ?? "#FFFFFF"))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: overlay.style.bg ?? "rgba(0,0,0,0.4)"))
                    )
                    .shadow(color: overlay.style.shadow ? Color.black.opacity(0.5) : .clear, radius: 4)
            }
        }
    }

    /// Arrow shape
    private func arrowShape(for overlay: Project.Overlay) -> some Shape {
        ArrowShape()
    }

    /// Calculate overlay position in canvas coordinates
    private func overlayPosition(for overlay: Project.Overlay) -> CGPoint {
        CGPoint(
            x: overlay.transform.x * canvasWidth,
            y: overlay.transform.y * canvasHeight
        )
    }

    /// Calculate overlay size based on scale
    private func overlaySize(for overlay: Project.Overlay) -> CGSize {
        let baseSize: CGSize
        switch overlay.type {
        case .arrow:
            baseSize = CGSize(width: 100, height: 100)
        case .rect:
            baseSize = CGSize(width: 150, height: 100)
        case .line:
            baseSize = CGSize(width: 150, height: 4)
        case .text:
            // Estimate text size
            baseSize = CGSize(width: 200, height: 50)
        }

        return CGSize(
            width: baseSize.width * overlay.transform.scale,
            height: baseSize.height * overlay.transform.scale
        )
    }

    /// Resize handle view
    private func resizeHandle(at handle: ResizeHandle, size: CGSize) -> some View {
        let handleSize: CGFloat = 12
        let offset: CGFloat = 6

        let position: CGPoint
        switch handle {
        case .topLeft:
            position = CGPoint(x: -size.width / 2 - offset, y: -size.height / 2 - offset)
        case .topRight:
            position = CGPoint(x: size.width / 2 + offset, y: -size.height / 2 - offset)
        case .bottomLeft:
            position = CGPoint(x: -size.width / 2 - offset, y: size.height / 2 + offset)
        case .bottomRight:
            position = CGPoint(x: size.width / 2 + offset, y: size.height / 2 + offset)
        }

        return Circle()
            .fill(Color.white)
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: handleSize, height: handleSize)
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        handleResizeChanged(value, handle: handle)
                    }
                    .onEnded { value in
                        handleResizeEnded(value, handle: handle)
                    }
            )
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Canvas-level drag (pan, etc.)
        dragOffset = value.translation
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        dragOffset = .zero
    }

    private func handleOverlayDragChanged(_ value: DragGesture.Value, for overlay: Project.Overlay) {
        guard initialTransform == nil else { return }
        initialTransform = overlay.transform

        var updatedTransform = overlay.transform
        updatedTransform.x += value.translation.width / canvasWidth
        updatedTransform.y += value.translation.height / canvasHeight

        Task { @MainActor in
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                transform: updatedTransform
            )
        }
    }

    private func handleOverlayDragEnded(_ value: DragGesture.Value, for overlay: Project.Overlay) {
        initialTransform = nil
    }

    private func handleResizeChanged(_ value: DragGesture.Value, handle: ResizeHandle) {
        guard let overlayId = selectedOverlayId,
              let overlay = projectEditor.project.overlays.first(where: { $0.id == overlayId }),
              initialSize == nil else { return }

        initialSize = overlaySize(for: overlay)

        let deltaScale = calculateScaleDelta(value.translation, handle: handle)
        var updatedTransform = overlay.transform
        updatedTransform.scale = max(0.1, overlay.transform.scale * deltaScale)

        Task { @MainActor in
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                transform: updatedTransform
            )
        }
    }

    private func handleResizeEnded(_ value: DragGesture.Value, handle: ResizeHandle) {
        initialSize = nil
    }

    private func calculateScaleDelta(_ translation: CGSize, handle: ResizeHandle) -> Double {
        let delta = sqrt(translation.width * translation.width + translation.height * translation.height)
        let baseSize: CGFloat = 100
        let scaleFactor = 1.0 + (delta / baseSize)

        return handle == .topLeft || handle == .topRight ? scaleFactor : 1.0 / scaleFactor
    }

    private func selectOverlay(_ id: UUID) {
        selectedOverlayId = id
        showStyleInspector = true
    }

    private func deselectOverlay() {
        selectedOverlayId = nil
        showStyleInspector = false
    }
}

// MARK: - Style Inspector View

struct StyleInspectorView: View {
    let overlay: Project.Overlay
    let projectEditor: ProjectEditor
    @Binding var isVisible: Bool

    @State private var strokeColor: String
    @State private var strokeWidth: Double
    @State private var shadow: Bool
    @State private var textColor: String
    @State private var textSize: Double
    @State private var backgroundColor: String
    @State private var startTime: Double
    @State private var endTime: Double

    init(overlay: Project.Overlay, projectEditor: ProjectEditor, isVisible: Binding<Bool>) {
        self.overlay = overlay
        self.projectEditor = projectEditor
        self._isVisible = isVisible

        self._strokeColor = State(initialValue: overlay.style.stroke)
        self._strokeWidth = State(initialValue: overlay.style.strokeWidth)
        self._shadow = State(initialValue: overlay.style.shadow)
        self._textColor = State(initialValue: overlay.style.color ?? "#FFFFFF")
        self._textSize = State(initialValue: overlay.style.size ?? 36)
        self._backgroundColor = State(initialValue: overlay.style.bg ?? "rgba(0,0,0,0.4)")
        self._startTime = State(initialValue: overlay.start)
        self._endTime = State(initialValue: overlay.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Style Inspector")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    isVisible = false
                }
            }

            Divider()

            // Timing controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Timing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                styleControl("Start Time") {
                    Slider(value: $startTime, in: 0...projectEditor.project.timeline.duration, step: 0.1)
                        .frame(width: 150)
                    Text("\(String(format: "%.1f", startTime))s")
                        .frame(width: 50)
                }
                .onChange(of: startTime) { _, newValue in
                    updateStartTime(newValue)
                }

                styleControl("End Time") {
                    Slider(value: $endTime, in: 0...projectEditor.project.timeline.duration, step: 0.1)
                        .frame(width: 150)
                    Text("\(String(format: "%.1f", endTime))s")
                        .frame(width: 50)
                }
                .onChange(of: endTime) { _, newValue in
                    updateEndTime(newValue)
                }

                styleControl("Duration") {
                    Text("\(String(format: "%.1f", endTime - startTime))s")
                        .frame(width: 50)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            Divider()

            // Common style controls
            styleControl("Stroke Color") {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: strokeColor) },
                    set: { newColor in
                        strokeColor = newColor.toHex() ?? strokeColor
                        updateStrokeColor(strokeColor)
                    }
                ))
            }

            styleControl("Stroke Width") {
                Slider(value: $strokeWidth, in: 1...20, step: 1)
                    .frame(width: 150)
                Text("\(Int(strokeWidth))px")
                    .frame(width: 40)
            }
            .onChange(of: strokeWidth) { _, newValue in
                updateStrokeWidth(newValue)
            }

            styleControl("Shadow") {
                Toggle("", isOn: $shadow)
                    .onChange(of: shadow) { _, newValue in
                        updateShadow(newValue)
                    }
            }

            // Text-specific controls
            if overlay.type == .text {
                styleControl("Text Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: textColor) },
                        set: { newColor in
                            textColor = newColor.toHex() ?? textColor
                            updateTextColor(textColor)
                        }
                    ))
                }

                styleControl("Text Size") {
                    Slider(value: $textSize, in: 12...72, step: 1)
                        .frame(width: 150)
                    Text("\(Int(textSize))")
                        .frame(width: 40)
                }
                .onChange(of: textSize) { _, newValue in
                    updateTextSize(newValue)
                }

                styleControl("Background Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: backgroundColor) },
                        set: { newColor in
                            backgroundColor = newColor.toHex() ?? backgroundColor
                            updateBackgroundColor(backgroundColor)
                        }
                    ))
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func styleControl<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func updateStrokeColor(_ color: String) {
        var updatedStyle = overlay.style
        updatedStyle.stroke = color

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateStrokeWidth(_ width: Double) {
        var updatedStyle = overlay.style
        updatedStyle.strokeWidth = width

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateShadow(_ enabled: Bool) {
        var updatedStyle = overlay.style
        updatedStyle.shadow = enabled

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateTextColor(_ color: String) {
        var updatedStyle = overlay.style
        updatedStyle.color = color

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateTextSize(_ size: Double) {
        var updatedStyle = overlay.style
        updatedStyle.size = size

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateBackgroundColor(_ color: String) {
        var updatedStyle = overlay.style
        updatedStyle.bg = color

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                style: updatedStyle
            )
        }
    }

    private func updateStartTime(_ time: Double) {
        // Ensure start time is less than end time
        let validatedTime = min(time, endTime - 0.1)

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                start: validatedTime
            )
        }
    }

    private func updateEndTime(_ time: Double) {
        // Ensure end time is greater than start time
        let validatedTime = max(time, startTime + 0.1)

        Task {
            try? await projectEditor.updateOverlay(
                overlayId: overlay.id,
                end: validatedTime
            )
        }
    }
}

// MARK: - Custom Shapes

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tailWidth = rect.width * 0.3
        let headWidth = rect.width
        let headLength = rect.height * 0.4

        // Draw arrow tail
        path.move(to: CGPoint(x: rect.midX - tailWidth / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - tailWidth / 2, y: rect.minY + headLength))

        // Draw arrow head
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + headLength))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + headLength))
        path.addLine(to: CGPoint(x: rect.midX + tailWidth / 2, y: rect.minY + headLength))

        // Complete tail
        path.addLine(to: CGPoint(x: rect.midX + tailWidth / 2, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct LineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        if hex.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else if hex.count == 8 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: hex.hasPrefix("rgba") ? 1.0 : 1.0
        )
    }

    func toHex() -> String? {
        #if os(iOS)
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(r * 255),
                      lroundf(g * 255),
                      lroundf(b * 255))
        #else
        guard let components = NSColor(self).usingColorSpace(.deviceRGB)?.components else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(r * 255),
                      lroundf(g * 255),
                      lroundf(b * 255))
        #endif
    }
}

// MARK: - Project Editor Extension

extension ProjectEditor {
    func updateOverlay(
        overlayId: UUID,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil
    ) async throws {
        let result = await editorModel.updateOverlay(
            projectId: project.projectId,
            overlayId: overlayId,
            transform: transform,
            style: style,
            start: start,
            end: end
        )

        switch result {
        case .success:
            // Reload project to get updated state
            let updatedProject = try await projectStore.loadProject(projectId: project.projectId)
            project = updatedProject
        case .failure(let error):
            throw error
        }
    }
}
