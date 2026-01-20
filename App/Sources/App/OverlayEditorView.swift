//
//  OverlayEditorView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-G — Overlay Editor (P0)
//

import SwiftUI
import EngineKit
import CoreGraphics

// MARK: - Main Overlay Editor View

struct OverlayEditorView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval

    @State private var selectedTool: OverlayTool = .arrow
    @State private var selectedOverlayId: UUID?
    @State private var isCreatingOverlay = false
    @State private var creationStartPoint: CGPoint = .zero
    @State private var creationCurrentPoint: CGPoint = .zero

    private let availableTools: [OverlayTool] = [.arrow, .rect, .line, .text]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toolbar
            toolbar

            Divider()

            // Canvas with overlays
            overlayCanvas

            // Style inspector (when overlay is selected)
            if let overlayId = selectedOverlayId,
               let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) {
                Divider()
                styleInspector(for: overlay)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Overlays")
                .font(.headline)

            Spacer()

            HStack(spacing: 4) {
                ForEach(availableTools, id: \.self) { tool in
                    toolButton(for: tool)
                }
            }

            Spacer()

            Button(action: deleteSelectedOverlay) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedOverlayId == nil)
        }
    }

    private func toolButton(for tool: OverlayTool) -> some View {
        Button(action: { selectTool(tool) }) {
            Label(tool.label, systemImage: tool.icon)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(tool.shortcut, modifiers: tool.modifiers)
        .background(selectedTool == tool ? Color.accentColor.opacity(0.3) : Color.clear)
    }

    private var overlayCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                // Background
                canvasBackground

                // Existing overlays
                ForEach(editor.project.overlays) { overlay in
                    renderOverlay(overlay, in: proxy.size)
                        .overlay(
                            selectionBorder(for: overlay)
                                .opacity(selectedOverlayId == overlay.id ? 1.0 : 0.0)
                        )
                        .gesture(dragGesture(for: overlay, in: proxy.size))
                        .gesture(resizeGesture(for: overlay, in: proxy.size))
                }

                // Creating overlay preview
                if isCreatingOverlay {
                    creationPreview
                }
            }
            .gesture(createOverlayGesture(in: proxy.size))
            .onTapGesture { location in
                // Deselect if tapping empty space
                if overlayAtPoint(location, in: proxy.size) == nil {
                    selectedOverlayId = nil
                }
            }
        }
        .frame(height: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }

    // MARK: - Overlay Rendering

    @ViewBuilder
    private func renderOverlay(_ overlay: Project.Overlay, in size: CoreFoundation.CGSize) -> some View {
        let rect = overlayRect(overlay, in: size)

        switch overlay.type {
        case .arrow:
            renderArrow(overlay, in: rect)
        case .rect:
            renderRectangle(overlay, in: rect)
        case .line:
            renderLine(overlay, in: rect)
        case .text:
            renderText(overlay, in: rect)
        }
    }

    private func renderArrow(_ overlay: Project.Overlay, in rect: CoreFoundation.CGRect) -> some View {
        let style = overlay.style

        return Path { path in
            let startPoint = CGPoint(x: rect.minX, y: rect.maxY)
            let endPoint = CGPoint(x: rect.maxX, y: rect.minY)

            // Line
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            // Arrowhead
            let arrowSize: CGFloat = 12
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let arrowPoint1 = CGPoint(
                x: endPoint.x - arrowSize * cos(angle - .pi / 6),
                y: endPoint.y - arrowSize * sin(angle - .pi / 6)
            )
            let arrowPoint2 = CGPoint(
                x: endPoint.x - arrowSize * cos(angle + .pi / 6),
                y: endPoint.y - arrowSize * sin(angle + .pi / 6)
            )

            path.move(to: endPoint)
            path.addLine(to: arrowPoint1)
            path.move(to: endPoint)
            path.addLine(to: arrowPoint2)
        }
        .stroke(color(from: overlay.style.stroke), lineWidth: style.strokeWidth)
        .shadow(style.shadow ? 2 : 0)
    }

    private func renderRectangle(_ overlay: Project.Overlay, in rect: CoreFoundation.CGRect) -> some View {
        let style = overlay.style

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(color(from: style.stroke), lineWidth: style.strokeWidth)
            .background(style.bg.map { color(from: $0).opacity(0.3) })
            .shadow(style.shadow ? 2 : 0)
    }

    private func renderLine(_ overlay: Project.Overlay, in rect: CoreFoundation.CGRect) -> some View {
        let style = overlay.style

        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        .stroke(color(from: style.stroke), lineWidth: style.strokeWidth)
        .shadow(style.shadow ? 2 : 0)
    }

    private func renderText(_ overlay: Project.Overlay, in rect: CoreFoundation.CGRect) -> some View {
        let style = overlay.style
        let fontName = style.font ?? "Helvetica"
        let fontSize = style.size ?? 24
        let textColor = style.color.map { color(from: $0) } ?? .primary

        return Text(style.text ?? "Text")
            .font(.custom(fontName, size: fontSize))
            .foregroundColor(textColor)
            .frame(width: rect.width, height: rect.height)
            .background(style.bg.map { color(from: $0).opacity(0.5) })
            .shadow(style.shadow ? 2 : 0)
    }

    // MARK: - Selection and Handles

    @ViewBuilder
    private func selectionBorder(for overlay: Project.Overlay) -> some View {
        let rect = overlayRect(overlay, in: CGSize(width: 800, height: 300)) // Approximate

        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: rect.width + 8, height: rect.height + 8)
    }

    // MARK: - Gestures

    private func createOverlayGesture(in size: CoreGraphics.CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isCreatingOverlay {
                    isCreatingOverlay = true
                    creationStartPoint = value.startLocation
                    creationCurrentPoint = value.location
                } else {
                    creationCurrentPoint = value.location
                }
            }
            .onEnded { value in
                let startPoint = normalizedPoint(creationStartPoint, in: size)
                let endPoint = normalizedPoint(value.location, in: size)

                createOverlay(from: startPoint, to: endPoint)

                isCreatingOverlay = false
                creationStartPoint = .zero
                creationCurrentPoint = .zero
            }
    }

    private func dragGesture(for overlay: Project.Overlay, in size: CoreGraphics.CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedOverlayId == overlay.id else { return }

                let deltaX = Double(value.translation.width / size.width)
                let deltaY = Double(value.translation.height / size.height)

                Task {
                    _ = await editor.updateOverlay(
                        projectId: editor.project.projectId,
                        overlayId: overlay.id,
                        transform: Project.Overlay.Transform(
                            x: overlay.transform.x + deltaX,
                            y: overlay.transform.y + deltaY,
                            scale: overlay.transform.scale,
                            rotation: overlay.transform.rotation
                        )
                    )
                }
            }
    }

    private func resizeGesture(for overlay: Project.Overlay, in size: CoreGraphics.CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedOverlayId == overlay.id else { return }

                // Calculate scale based on drag distance
                let scaleDelta = Double(value.translation.width / 100.0)
                let newScale = max(0.1, overlay.transform.scale + scaleDelta)

                Task {
                    _ = await editor.updateOverlay(
                        projectId: editor.project.projectId,
                        overlayId: overlay.id,
                        transform: Project.Overlay.Transform(
                            x: overlay.transform.x,
                            y: overlay.transform.y,
                            scale: newScale,
                            rotation: overlay.transform.rotation
                        )
                    )
                }
            }
    }

    // MARK: - Overlay Creation

    private var creationPreview: some View {
        let rect = CGRect(
            x: min(creationStartPoint.x, creationCurrentPoint.x),
            y: min(creationStartPoint.y, creationCurrentPoint.y),
            width: abs(creationCurrentPoint.x - creationStartPoint.x),
            height: abs(creationCurrentPoint.y - creationStartPoint.y)
        )

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func createOverlay(from start: CGPoint, to end: CGPoint) {
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        guard width > 0.01 || height > 0.01 else { return }

        let centerX = min(start.x, end.x) + width / 2.0
        let centerY = min(start.y, end.y) + height / 2.0

        let overlay = Project.Overlay(
            id: UUID(),
            type: selectedTool.overlayType,
            start: playheadTime,
            end: playheadTime + 5.0, // Default 5 seconds
            transform: Project.Overlay.Transform(
                x: centerX,
                y: centerY,
                scale: 1.0,
                rotation: 0.0
            ),
            style: defaultStyle(for: selectedTool),
            animation: nil
        )

        Task {
            _ = await editor.addOverlay(projectId: editor.project.id, overlay: overlay)
            selectedOverlayId = overlay.id
        }
    }

    // MARK: - Style Inspector

    @ViewBuilder
    private func styleInspector(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style Inspector")
                .font(.headline)

            HStack(spacing: 16) {
                // Color picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.subheadline)
                    ColorPicker("", selection: Binding(
                        get: { color(from: overlay.style.stroke) },
                        set: { newColor in updateOverlay(style: overlay.style.with(stroke: hexColor(from: newColor))) }
                    ))
                    .labelsHidden()
                }

                // Stroke width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stroke Width")
                        .font(.subheadline)
                    Slider(
                        value: Binding(
                            get: { overlay.style.strokeWidth },
                            set: { updateOverlay(style: overlay.style.with(strokeWidth: $0)) }
                        ),
                        in: 1...10,
                        step: 0.5
                    )
                    .frame(maxWidth: 120)
                }

                // Shadow toggle
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shadow")
                        .font(.subheadline)
                    Toggle("", isOn: Binding(
                        get: { overlay.style.shadow },
                        set: { updateOverlay(style: overlay.style.with(shadow: $0)) }
                    ))
                    .labelsHidden()
                }
            }

            // Text-specific controls
            if overlay.type == .text {
                textSpecificControls(for: overlay)
            }

            // Animation controls
            animationControls(for: overlay)

            // Timing controls
            timingControls(for: overlay)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func textSpecificControls(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.subheadline)

            TextField("Text", text: Binding(
                get: { overlay.style.text ?? "" },
                set: { updateOverlay(style: overlay.style.with(text: $0)) }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font")
                        .font(.caption)
                    Picker("", selection: Binding(
                        get: { overlay.style.font ?? "Helvetica" },
                        set: { updateOverlay(style: overlay.style.with(font: $0)) }
                    )) {
                        Text("Helvetica").tag("Helvetica")
                        Text("Arial").tag("Arial")
                        Text("Courier").tag("Courier")
                        Text("Georgia").tag("Georgia")
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Size")
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { overlay.style.size ?? 24 },
                            set: { updateOverlay(style: overlay.style.with(size: $0)) }
                        ),
                        in: 12...72,
                        step: 1
                    )
                    .frame(maxWidth: 80)
                }
            }
        }
    }

    private func timingControls(for overlay: Project.Overlay) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Time")
                    .font(.subheadline)
                TextField("s", value: Binding(
                    get: { overlay.start },
                    set: { updateOverlay(start: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("End Time")
                    .font(.subheadline)
                TextField("s", value: Binding(
                    get: { overlay.end },
                    set: { updateOverlay(end: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.subheadline)
                Text("\(overlay.end - overlay.start, specifier: "%.1f")s")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func animationControls(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation")
                .font(.subheadline)

            // Animation type selector
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type")
                        .font(.caption)
                    Picker("", selection: Binding(
                        get: { overlay.animation?.type ?? .none },
                        set: { newType in updateOverlayAnimation(type: newType, overlay: overlay) }
                    )) {
                        Text("None").tag(Project.Overlay.Animation.AnimationType.none)
                        Text("Fade In").tag(Project.Overlay.Animation.AnimationType.fadeIn)
                        Text("Fade Out").tag(Project.Overlay.Animation.AnimationType.fadeOut)
                        Text("Fade In + Out").tag(Project.Overlay.Animation.AnimationType.fadeInOut)
                        Text("Draw On").tag(Project.Overlay.Animation.AnimationType.drawOn)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                // Duration controls (only show if animation is selected)
                if overlay.animation != nil && overlay.animation?.type != .none {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duration")
                            .font(.caption)
                        HStack(spacing: 8) {
                            if overlay.animation?.type == .fadeIn || overlay.animation?.type == .fadeInOut {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("In")
                                        .font(.caption2)
                                    TextField("s", value: Binding(
                                        get: { overlay.animation?.fadeInDuration ?? 0.3 },
                                        set: { updateOverlayAnimation(fadeInDuration: $0, overlay: overlay) }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                }
                            }

                            if overlay.animation?.type == .fadeOut || overlay.animation?.type == .fadeInOut {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Out")
                                        .font(.caption2)
                                    TextField("s", value: Binding(
                                        get: { overlay.animation?.fadeOutDuration ?? 0.3 },
                                        set: { updateOverlayAnimation(fadeOutDuration: $0, overlay: overlay) }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                }
                            }

                            if overlay.animation?.type == .drawOn {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Draw")
                                        .font(.caption2)
                                    TextField("s", value: Binding(
                                        get: { overlay.animation?.drawOnDuration ?? 0.5 },
                                        set: { updateOverlayAnimation(drawOnDuration: $0, overlay: overlay) }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                }
                            }
                        }
                    }

                    // Easing function selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Easing")
                            .font(.caption)
                        Picker("", selection: Binding(
                            get: { overlay.animation?.easing ?? .easeInOut },
                            set: { updateOverlayAnimation(easing: $0, overlay: overlay) }
                        )) {
                            Text("Linear").tag(Project.Overlay.Animation.EasingFunction.linear)
                            Text("Ease In").tag(Project.Overlay.Animation.EasingFunction.easeIn)
                            Text("Ease Out").tag(Project.Overlay.Animation.EasingFunction.easeOut)
                            Text("Ease In/Out").tag(Project.Overlay.Animation.EasingFunction.easeInOut)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func selectTool(_ tool: OverlayTool) {
        selectedTool = tool
        selectedOverlayId = nil
    }

    private func deleteSelectedOverlay() {
        guard let overlayId = selectedOverlayId else { return }

        Task {
            _ = await editor.deleteOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId
            )
            selectedOverlayId = nil
        }
    }

    private func updateOverlay(style: Project.Overlay.Style) {
        guard let overlayId = selectedOverlayId else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                style: style
            )
        }
    }

    private func updateOverlay(start: TimeInterval) {
        guard let overlayId = selectedOverlayId else { return }
        guard let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) else { return }
        guard start < overlay.end else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                start: start
            )
        }
    }

    private func updateOverlay(end: TimeInterval) {
        guard let overlayId = selectedOverlayId else { return }
        guard let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) else { return }
        guard end > overlay.start else { return }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                end: end
            )
        }
    }

    // MARK: - Animation Update Helpers

    private func updateOverlayAnimation(type: Project.Overlay.Animation.AnimationType, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }

        let animation: Project.Overlay.Animation?
        if type == .none {
            animation = nil
        } else {
            let currentAnimation = overlay.animation
            animation = Project.Overlay.Animation(
                type: type,
                fadeInDuration: currentAnimation?.fadeInDuration ?? 0.3,
                fadeOutDuration: currentAnimation?.fadeOutDuration ?? 0.3,
                drawOnDuration: currentAnimation?.drawOnDuration ?? 0.5,
                easing: currentAnimation?.easing ?? .easeInOut
            )
        }

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    private func updateOverlayAnimation(fadeInDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    private func updateOverlayAnimation(fadeOutDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    private func updateOverlayAnimation(drawOnDuration: TimeInterval, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: drawOnDuration,
            easing: currentAnimation.easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    private func updateOverlayAnimation(easing: Project.Overlay.Animation.EasingFunction, overlay: Project.Overlay) {
        guard let overlayId = selectedOverlayId else { return }
        guard let currentAnimation = overlay.animation else { return }

        let animation = Project.Overlay.Animation(
            type: currentAnimation.type,
            fadeInDuration: currentAnimation.fadeInDuration,
            fadeOutDuration: currentAnimation.fadeOutDuration,
            drawOnDuration: currentAnimation.drawOnDuration,
            easing: easing
        )

        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                animation: animation
            )
        }
    }

    // MARK: - Geometry Helpers

    private func overlayRect(_ overlay: Project.Overlay, in size: CoreFoundation.CGSize) -> CoreGraphics.CGRect {
        let x = overlay.transform.x * size.width
        let y = overlay.transform.y * size.height
        let width = 100 * overlay.transform.scale
        let height = 100 * overlay.transform.scale

        return CoreGraphics.CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    private func normalizedPoint(_ point: CoreFoundation.CGPoint, in size: CoreFoundation.CGSize) -> CoreFoundation.CGPoint {
        CoreFoundation.CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    private func overlayAtPoint(_ point: CoreGraphics.CGPoint, in size: CoreGraphics.CGSize) -> Project.Overlay? {
        for overlay in editor.project.overlays {
            let rect = overlayRect(overlay, in: size)
            if rect.contains(point) {
                return overlay
            }
        }
        return nil
    }

    private func defaultStyle(for tool: OverlayTool) -> Project.Overlay.Style {
        switch tool {
        case .arrow, .line:
            return Project.Overlay.Style(
                stroke: "#FF3B30",
                strokeWidth: 3.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            )
        case .rect:
            return Project.Overlay.Style(
                stroke: "#007AFF",
                strokeWidth: 2.0,
                shadow: true,
                font: nil,
                size: nil,
                color: nil,
                bg: "#007AFF",
                text: nil
            )
        case .text:
            return Project.Overlay.Style(
                stroke: "#000000",
                strokeWidth: 0.0,
                shadow: false,
                font: "Helvetica",
                size: 24.0,
                color: "#000000",
                bg: nil,
                text: "Text"
            )
        }
    }

    private func color(from hex: String) -> Color {
        guard let rgba = rgba(from: hex) else {
            return .primary
        }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    private func rgba(from hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 6: // RGB
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8: // ARGB
            r = Double((rgb & 0x00FF0000) >> 16) / 255.0
            g = Double((rgb & 0x0000FF00) >> 8) / 255.0
            b = Double(rgb & 0x000000FF) / 255.0
            a = Double((rgb & 0xFF000000) >> 24) / 255.0
        default:
            return nil
        }

        return (r, g, b, a)
    }

    private func hexColor(from color: Color) -> String {
        // Default to red if conversion fails
        return "#FF3B30"
    }
}

// MARK: - Overlay Tool Enum

enum OverlayTool: CaseIterable {
    case arrow
    case rect
    case line
    case text

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
        case .line: return "Line"
        case .text: return "Text"
        }
    }

    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        }
    }

    var overlayType: Project.Overlay.OverlayType {
        switch self {
        case .arrow: return .arrow
        case .rect: return .rect
        case .line: return .line
        case .text: return .text
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .arrow: return "a"
        case .rect: return "r"
        case .line: return "l"
        case .text: return "t"
        }
    }

    var modifiers: EventModifiers {
        .command
    }
}

// MARK: - Project.Overlay.Style Extensions

extension Project.Overlay.Style {
    func with(stroke: String) -> Project.Overlay.Style {
        var copy = self
        copy.stroke = stroke
        return copy
    }

    func with(strokeWidth: Double) -> Project.Overlay.Style {
        var copy = self
        copy.strokeWidth = strokeWidth
        return copy
    }

    func with(shadow: Bool) -> Project.Overlay.Style {
        var copy = self
        copy.shadow = shadow
        return copy
    }

    func with(font: String) -> Project.Overlay.Style {
        var copy = self
        copy.font = font
        return copy
    }

    func with(size: Double) -> Project.Overlay.Style {
        var copy = self
        copy.size = size
        return copy
    }

    func with(color: String) -> Project.Overlay.Style {
        var copy = self
        copy.color = color
        return copy
    }

    func with(bg: String) -> Project.Overlay.Style {
        var copy = self
        copy.bg = bg
        return copy
    }

    func with(text: String) -> Project.Overlay.Style {
        var copy = self
        copy.text = text
        return copy
    }
}
