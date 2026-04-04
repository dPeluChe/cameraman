//
//  OverlayPopover.swift
//  App
//
//  Popover for editing overlay properties.
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
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                        .font(.system(size: 16))
                        .foregroundStyle(.cyan)
                    Text(OverlayDisplayInfo.label(for: overlay.type))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1fs", overlay.end - overlay.start))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Position
                        popoverSection("Position") {
                            // Preset grid
                            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                                GridRow {
                                    presetBtn(.topLeft, overlay)
                                    presetBtn(.topCenter, overlay)
                                    presetBtn(.topRight, overlay)
                                }
                                GridRow {
                                    presetBtn(.centerLeft, overlay)
                                    presetBtn(.center, overlay)
                                    presetBtn(.centerRight, overlay)
                                }
                                GridRow {
                                    presetBtn(.bottomLeft, overlay)
                                    presetBtn(.bottomCenter, overlay)
                                    presetBtn(.bottomRight, overlay)
                                }
                            }

                            // Fine-tune sliders
                            labeledSlider("X", value: sliderBinding(overlay, \.transform.x), range: 0...1,
                                          display: String(format: "%.0f%%", overlay.transform.x * 100))
                            labeledSlider("Y", value: sliderBinding(overlay, \.transform.y), range: 0...1,
                                          display: String(format: "%.0f%%", overlay.transform.y * 100))
                        }

                        // Transform
                        popoverSection("Transform") {
                            labeledSlider("Scale", value: sliderBinding(overlay, \.transform.scale), range: 0.2...3.0,
                                          display: String(format: "%.1fx", overlay.transform.scale))
                            labeledSlider("Rotation", value: sliderBinding(overlay, \.transform.rotation), range: -180...180,
                                          display: String(format: "%.0f°", overlay.transform.rotation))
                        }

                        // Style
                        popoverSection("Style") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Color")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: overlay.style.stroke) },
                                        set: { newColor in
                                            mutate(overlay) { $0.style.stroke = hexString(from: newColor) }
                                        }
                                    ))
                                    .labelsHidden()
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shadow")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Toggle("", isOn: Binding(
                                        get: { overlay.style.shadow },
                                        set: { val in mutate(overlay) { $0.style.shadow = val } }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .labelsHidden()
                                }
                            }

                            labeledSlider("Stroke", value: sliderBinding(overlay, \.style.strokeWidth), range: 1...10,
                                          display: String(format: "%.1f", overlay.style.strokeWidth))
                        }

                        // Text (only for text type)
                        if overlay.type == .text {
                            popoverSection("Text") {
                                TextField("Content", text: Binding(
                                    get: { overlay.style.text ?? "" },
                                    set: { val in mutate(overlay) { $0.style.text = val } }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                                labeledSlider("Size", value: optionalSliderBinding(overlay, \.style.size, default: 24),
                                              range: 12...72,
                                              display: String(format: "%.0fpt", overlay.style.size ?? 24))
                            }
                        }

                        // Delete
                        Button(role: .destructive) {
                            Task {
                                _ = await editor.deleteOverlay(projectId: editor.project.projectId, overlayId: overlayId)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Overlay")
                            }
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(16)
                }
            }
            .frame(width: 260)
            .frame(maxHeight: 480)
        }
    }

    // MARK: - Components

    private func popoverSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil, display: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            if let step {
                Slider(value: value, in: range, step: step)
                    .controlSize(.small)
            } else {
                Slider(value: value, in: range)
                    .controlSize(.small)
            }

            Text(display)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func presetBtn(_ preset: PositionPreset, _ overlay: Project.Overlay) -> some View {
        let isActive = abs(overlay.transform.x - preset.x) < 0.06 && abs(overlay.transform.y - preset.y) < 0.06
        return Button {
            mutate(overlay) { $0.transform.x = preset.x; $0.transform.y = preset.y }
        } label: {
            Image(systemName: preset.icon)
                .font(.system(size: 11))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(preset.label)
    }

    // MARK: - Helpers

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

    private func optionalSliderBinding(_ overlay: Project.Overlay, _ kp: WritableKeyPath<Project.Overlay, Double?>, default defaultVal: Double) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: kp] ?? defaultVal },
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
