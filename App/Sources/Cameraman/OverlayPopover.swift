//
//  OverlayPopover.swift
//  App
//
//  Compact popover for editing overlay properties.
//  Appears on second click of an overlay in the timeline.
//

import SwiftUI
import EngineKit

struct OverlayPopoverContent: View {
    @ObservedObject var editor: ProjectEditor
    let overlayId: UUID

    private var overlay: Project.Overlay? {
        editor.project.overlays.first { $0.id == overlayId }
    }

    var body: some View {
        if let overlay {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                    Text(OverlayDisplayInfo.label(for: overlay.type))
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.1fs", overlay.end - overlay.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Position presets (3x3 grid)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Position")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        ForEach(Array(PositionPreset.allCases.prefix(3)), id: \.self) { p in
                            presetButton(p, overlay)
                        }
                        Spacer()
                        // X/Y values
                        Text(String(format: "%.0f%%, %.0f%%", overlay.transform.x * 100, overlay.transform.y * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 2) {
                        ForEach(Array(PositionPreset.allCases.dropFirst(3).prefix(3)), id: \.self) { p in
                            presetButton(p, overlay)
                        }
                    }
                    HStack(spacing: 2) {
                        ForEach(Array(PositionPreset.allCases.suffix(3)), id: \.self) { p in
                            presetButton(p, overlay)
                        }
                    }
                }

                // Scale + Rotation
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scale \(String(format: "%.1fx", overlay.transform.scale))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: sliderBinding(overlay, \.transform.scale), in: 0.2...3.0)
                            .controlSize(.mini)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rotate \(String(format: "%.0f°", overlay.transform.rotation))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: sliderBinding(overlay, \.transform.rotation), in: -180...180)
                            .controlSize(.mini)
                    }
                }

                Divider()

                // Style row
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: overlay.style.stroke) },
                        set: { newColor in
                            let hex = hexString(from: newColor)
                            mutate(overlay) { $0.style.stroke = hex }
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Width")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: sliderBinding(overlay, \.style.strokeWidth), in: 1...10, step: 0.5)
                            .controlSize(.mini)
                    }

                    Toggle("", isOn: Binding(
                        get: { overlay.style.shadow },
                        set: { val in mutate(overlay) { $0.style.shadow = val } }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Shadow")
                }

                // Text content (only for text overlays)
                if overlay.type == .text {
                    TextField("Text", text: Binding(
                        get: { overlay.style.text ?? "" },
                        set: { val in mutate(overlay) { $0.style.text = val } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                Divider()

                // Delete
                Button(role: .destructive) {
                    Task {
                        _ = await editor.deleteOverlay(projectId: editor.project.projectId, overlayId: overlayId)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .frame(width: 220)
        }
    }

    // MARK: - Helpers

    private func presetButton(_ preset: PositionPreset, _ overlay: Project.Overlay) -> some View {
        let isActive = abs(overlay.transform.x - preset.x) < 0.05 && abs(overlay.transform.y - preset.y) < 0.05
        return Button {
            mutate(overlay) { $0.transform.x = preset.x; $0.transform.y = preset.y }
        } label: {
            Image(systemName: preset.icon)
                .font(.system(size: 9))
                .frame(width: 22, height: 22)
                .background(isActive ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(preset.label)
    }

    private func mutate(_ overlay: Project.Overlay, _ block: (inout Project.Overlay) -> Void) {
        var updated = overlay
        block(&updated)
        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                transform: updated.transform,
                style: updated.style
            )
        }
    }

    private func sliderBinding(_ overlay: Project.Overlay, _ kp: WritableKeyPath<Project.Overlay, Double>) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: kp] },
            set: { val in mutate(overlay) { $0[keyPath: kp] = val } }
        )
    }

    private func hexString(from color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - Position Presets

enum PositionPreset: CaseIterable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    var x: Double {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return 0.15
        case .topCenter, .center, .bottomCenter: return 0.5
        case .topRight, .centerRight, .bottomRight: return 0.85
        }
    }

    var y: Double {
        switch self {
        case .topLeft, .topCenter, .topRight: return 0.15
        case .centerLeft, .center, .centerRight: return 0.5
        case .bottomLeft, .bottomCenter, .bottomRight: return 0.85
        }
    }

    var icon: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topCenter: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .centerLeft: return "arrow.left"
        case .center: return "circle.fill"
        case .centerRight: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .centerLeft: return "Center Left"
        case .center: return "Center"
        case .centerRight: return "Center Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}
