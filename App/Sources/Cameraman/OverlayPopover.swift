//
//  OverlayPopover.swift
//  App
//
//  Popover inspector for overlay properties. Appears when an overlay
//  is selected in the timeline.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(overlay)
                    Divider()
                    positionSection(overlay)
                    Divider()
                    styleSection(overlay)
                    if overlay.type == .text {
                        Divider()
                        textSection(overlay)
                    }
                    Divider()
                    timingSection(overlay)
                    Divider()
                    deleteSection
                }
                .padding(14)
            }
            .frame(width: 280)
            .frame(maxHeight: 420)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ overlay: Project.Overlay) -> some View {
        HStack {
            Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                .font(.title3)
            Text(OverlayDisplayInfo.label(for: overlay.type))
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Position & Transform

    @ViewBuilder
    private func positionSection(_ overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.subheadline.bold())

            HStack(spacing: 12) {
                compactField("X", value: overlay.transform.x, range: 0...1) { newVal in
                    update(overlay) { $0.transform.x = newVal }
                }
                compactField("Y", value: overlay.transform.y, range: 0...1) { newVal in
                    update(overlay) { $0.transform.y = newVal }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: binding(overlay, \.transform.scale, min: 0.1, max: 3.0), in: 0.1...3.0)
                        .controlSize(.small)
                }
                Text(String(format: "%.1fx", overlay.transform.scale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rotation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: binding(overlay, \.transform.rotation, min: -180, max: 180), in: -180...180)
                        .controlSize(.small)
                }
                Text(String(format: "%.0f°", overlay.transform.rotation))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }

            // Quick position presets
            HStack(spacing: 4) {
                ForEach(PositionPreset.allCases, id: \.self) { preset in
                    Button {
                        update(overlay) {
                            $0.transform.x = preset.x
                            $0.transform.y = preset.y
                        }
                    } label: {
                        Image(systemName: preset.icon)
                            .font(.system(size: 10))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(preset.label)
                }
            }
        }
    }

    // MARK: - Style

    @ViewBuilder
    private func styleSection(_ overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.subheadline.bold())

            HStack(spacing: 12) {
                ColorPicker("Color", selection: Binding(
                    get: { Color(hex: overlay.style.stroke) },
                    set: { newColor in
                        let hex = hexString(from: newColor)
                        update(overlay) { $0.style.stroke = hex }
                    }
                ))
                .labelsHidden()
                .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stroke")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: binding(overlay, \.style.strokeWidth, min: 1, max: 10), in: 1...10, step: 0.5)
                        .controlSize(.small)
                }

                Toggle("Shadow", isOn: Binding(
                    get: { overlay.style.shadow },
                    set: { newVal in update(overlay) { $0.style.shadow = newVal } }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func textSection(_ overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.subheadline.bold())

            TextField("Content", text: Binding(
                get: { overlay.style.text ?? "" },
                set: { newText in update(overlay) { $0.style.text = newText } }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: binding(overlay, \.style.size, default: 24, min: 12, max: 72), in: 12...72, step: 1)
                        .controlSize(.small)
                }
                Text(String(format: "%.0fpt", overlay.style.size ?? 24))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 35)
            }
        }
    }

    // MARK: - Timing

    @ViewBuilder
    private func timingSection(_ overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing")
                .font(.subheadline.bold())

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fs", overlay.start))
                        .font(.caption.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fs", overlay.end))
                        .font(.caption.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fs", overlay.end - overlay.start))
                        .font(.caption.monospacedDigit())
                }
                Spacer()
            }
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            Task {
                _ = await editor.deleteOverlay(
                    projectId: editor.project.projectId,
                    overlayId: overlayId
                )
            }
        } label: {
            Label("Delete Overlay", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
    }

    // MARK: - Helpers

    private func update(_ overlay: Project.Overlay, _ mutate: (inout Project.Overlay) -> Void) {
        var updated = overlay
        mutate(&updated)
        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                transform: updated.transform,
                style: updated.style
            )
        }
    }

    private func compactField(_ label: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range)
            .controlSize(.small)
        }
    }

    private func hexString(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func binding(_ overlay: Project.Overlay, _ keyPath: WritableKeyPath<Project.Overlay, Double>, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: keyPath] },
            set: { newVal in
                update(overlay) { $0[keyPath: keyPath] = Swift.min(max, Swift.max(min, newVal)) }
            }
        )
    }

    private func binding(_ overlay: Project.Overlay, _ keyPath: WritableKeyPath<Project.Overlay, Double?>, default defaultVal: Double, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: keyPath] ?? defaultVal },
            set: { newVal in
                update(overlay) { $0[keyPath: keyPath] = Swift.min(max, Swift.max(min, newVal)) }
            }
        )
    }
}

// MARK: - Position Presets

private enum PositionPreset: CaseIterable {
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
