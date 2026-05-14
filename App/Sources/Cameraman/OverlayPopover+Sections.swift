//
//  OverlayPopover+Sections.swift
//  App
//
//  Section builders for OverlayPopoverContent. Each builder owns one logical
//  group of controls (timing / animation / position / transform / style) and
//  closes over the popover's @State + helpers. Extension in the same module
//  keeps private member access while letting the main file focus on the
//  body + bindings.
//

import AppKit
import SwiftUI
import EngineKit
import UniformTypeIdentifiers

extension OverlayPopoverContent {

    // MARK: - Sections (in display order)

    @ViewBuilder
    func timingSection(overlay: Project.Overlay) -> some View {
        popoverSection("Timing") {
            let maxDuration = editor.project.timeline.duration
            labeledSlider(
                "Start",
                value: timingBinding(overlay, isStart: true, maxDuration: maxDuration),
                range: 0...maxDuration,
                display: String(format: "%.1fs", draftStart ?? overlay.start),
                onEditingChanged: { editing in
                    if !editing { commitTiming(isStart: true, overlay: overlay) }
                }
            )
            labeledSlider(
                "End",
                value: timingBinding(overlay, isStart: false, maxDuration: maxDuration),
                range: 0...maxDuration,
                display: String(format: "%.1fs", draftEnd ?? overlay.end),
                onEditingChanged: { editing in
                    if !editing { commitTiming(isStart: false, overlay: overlay) }
                }
            )
            HStack {
                Text("Duration")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fs", overlay.end - overlay.start))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    func animationSection(overlay: Project.Overlay) -> some View {
        popoverSection("Animation") {
            HStack(spacing: 8) {
                Text("Type")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Picker("", selection: Binding(
                    get: { overlay.animation?.type ?? .none },
                    set: { val in
                        mutate(overlay) { o in
                            if val == .none {
                                o.animation = nil
                            } else {
                                let current = o.animation
                                o.animation = Project.Overlay.Animation(
                                    type: val,
                                    fadeInDuration: current?.fadeInDuration ?? 0.3,
                                    fadeOutDuration: current?.fadeOutDuration ?? 0.3,
                                    drawOnDuration: current?.drawOnDuration ?? 0.5,
                                    easing: current?.easing ?? .easeInOut
                                )
                            }
                        }
                    }
                )) {
                    Text("None").tag(Project.Overlay.Animation.AnimationType.none)
                    Text("Fade In").tag(Project.Overlay.Animation.AnimationType.fadeIn)
                    Text("Fade Out").tag(Project.Overlay.Animation.AnimationType.fadeOut)
                    Text("Fade In/Out").tag(Project.Overlay.Animation.AnimationType.fadeInOut)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
            }

            // Only show fade duration sliders when there's an active fade.
            let animType = overlay.animation?.type ?? .none
            let maxFade = max(0.05, overlay.end - overlay.start)
            if animType == .fadeIn || animType == .fadeInOut {
                labeledSlider(
                    "In",
                    value: fadeBinding(overlay, isIn: true, maxFade: maxFade),
                    range: 0.05...maxFade,
                    display: String(format: "%.2fs", overlay.animation?.fadeInDuration ?? 0)
                )
            }
            if animType == .fadeOut || animType == .fadeInOut {
                labeledSlider(
                    "Out",
                    value: fadeBinding(overlay, isIn: false, maxFade: maxFade),
                    range: 0.05...maxFade,
                    display: String(format: "%.2fs", overlay.animation?.fadeOutDuration ?? 0)
                )
            }
        }
    }

    @ViewBuilder
    func positionSection(overlay: Project.Overlay) -> some View {
        popoverSection("Position") {
            OverlayPositionCanvas(
                overlay: overlay,
                onPositionChange: { x, y in
                    mutate(overlay) { $0.transform.x = x; $0.transform.y = y }
                }
            )
            labeledSlider("X", value: sliderBinding(overlay, \.transform.x), range: 0...1,
                          display: String(format: "%.0f%%", overlay.transform.x * 100))
            labeledSlider("Y", value: sliderBinding(overlay, \.transform.y), range: 0...1,
                          display: String(format: "%.0f%%", overlay.transform.y * 100))
        }
    }

    @ViewBuilder
    func transformSection(overlay: Project.Overlay) -> some View {
        popoverSection("Transform") {
            labeledSlider("Scale", value: sliderBinding(overlay, \.transform.scale), range: 0.2...3.0,
                          display: String(format: "%.1fx", overlay.transform.scale))
            labeledSlider("Rotation", value: sliderBinding(overlay, \.transform.rotation), range: -180...180,
                          display: String(format: "%.0f°", overlay.transform.rotation))
        }
    }

    @ViewBuilder
    func styleSection(overlay: Project.Overlay) -> some View {
        switch overlay.type {
        case .arrow, .rect, .line:
            popoverSection("Style") {
                HStack(spacing: 16) {
                    smallLabeled("Color") {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: overlay.style.stroke) },
                            set: { newColor in
                                mutate(overlay) { $0.style.stroke = hexString(from: newColor) }
                            }
                        ))
                        .labelsHidden()
                    }
                    smallLabeled("Shadow") {
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

        case .text:
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

                HStack(spacing: 16) {
                    smallLabeled("Color") {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: overlay.style.color ?? "#FFFFFF") },
                            set: { newColor in
                                mutate(overlay) { $0.style.color = hexString(from: newColor) }
                            }
                        ))
                        .labelsHidden()
                    }
                    smallLabeled("Shadow") {
                        Toggle("", isOn: Binding(
                            get: { overlay.style.shadow },
                            set: { val in mutate(overlay) { $0.style.shadow = val } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }
            }

        case .image:
            popoverSection("Image") {
                let filename = (overlay.style.imagePath as NSString?)?.lastPathComponent ?? "(no file)"
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(filename)
                        .font(.system(size: 11).monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
                labeledSlider(
                    "Opacity",
                    value: optionalSliderBinding(overlay, \.style.imageOpacity, default: 1.0),
                    range: 0...1,
                    display: String(format: "%.0f%%", (overlay.style.imageOpacity ?? 1.0) * 100)
                )
                Button {
                    presentChangeImagePanel(overlay: overlay)
                } label: {
                    Label("Change Image…", systemImage: "photo.badge.plus")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    var deleteButton: some View {
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

    // MARK: - Reusable components

    @ViewBuilder
    func smallLabeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
    }

    func popoverSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    func labeledSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        display: String,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            if let step {
                Slider(value: value, in: range, step: step, onEditingChanged: { editing in
                    onEditingChanged?(editing)
                })
                    .controlSize(.small)
            } else {
                Slider(value: value, in: range, onEditingChanged: { editing in
                    onEditingChanged?(editing)
                })
                    .controlSize(.small)
            }

            Text(display)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Animation helpers

    func fadeBinding(_ overlay: Project.Overlay, isIn: Bool, maxFade: TimeInterval) -> Binding<Double> {
        Binding(
            get: {
                isIn ? (overlay.animation?.fadeInDuration ?? 0.3) : (overlay.animation?.fadeOutDuration ?? 0.3)
            },
            set: { val in
                mutate(overlay) { o in
                    let current = o.animation ?? Project.Overlay.Animation(type: .fadeInOut)
                    o.animation = Project.Overlay.Animation(
                        type: current.type == .none ? .fadeInOut : current.type,
                        fadeInDuration: isIn ? min(val, maxFade) : current.fadeInDuration,
                        fadeOutDuration: !isIn ? min(val, maxFade) : current.fadeOutDuration,
                        drawOnDuration: current.drawOnDuration,
                        easing: current.easing
                    )
                }
            }
        )
    }

    // MARK: - Image change picker

    func presentChangeImagePanel(overlay: Project.Overlay) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a replacement image"
        panel.allowedContentTypes = [.image, .svg, .gif]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                mutate(overlay) { $0.style.imagePath = url.path }
            }
        }
    }
}
