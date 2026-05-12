//
//  OverlayInspector.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    // MARK: - Style Inspector
    private var inspectorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 86, maximum: 140), spacing: 12)]
    }

    @ViewBuilder
    func styleInspector(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style Inspector")
                .font(.headline)

            LazyVGrid(columns: inspectorColumns, alignment: .leading, spacing: 12) {
                // Color picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.caption)
                    ColorPicker("", selection: Binding(
                        get: { color(from: overlay.style.stroke) },
                        set: { newColor in updateOverlay(style: overlay.style.with(stroke: hexColor(from: newColor))) }
                    ))
                    .labelsHidden()
                }

                // Stroke width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stroke Width")
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { overlay.style.strokeWidth },
                            set: { updateOverlay(style: overlay.style.with(strokeWidth: $0)) }
                        ),
                        in: 1...10,
                        step: 0.5
                    )
                }

                // Shadow toggle
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shadow")
                        .font(.caption)
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

    func textSpecificControls(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.subheadline)

            TextField("Text", text: Binding(
                get: { overlay.style.text ?? "" },
                set: { updateOverlay(style: overlay.style.with(text: $0)) }
            ))
            .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: inspectorColumns, alignment: .leading, spacing: 12) {
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
                }
            }
        }
    }

    func timingControls(for overlay: Project.Overlay) -> some View {
        LazyVGrid(columns: inspectorColumns, alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Time")
                    .font(.caption)
                TextField("s", value: Binding(
                    get: { overlay.start },
                    set: { updateOverlay(start: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("End Time")
                    .font(.caption)
                TextField("s", value: Binding(
                    get: { overlay.end },
                    set: { updateOverlay(end: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                Text("\(overlay.end - overlay.start, specifier: "%.1f")s")
                    .foregroundStyle(.secondary)
            }
        }
    }

    func animationControls(for overlay: Project.Overlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation")
                .font(.subheadline)

            // Animation type selector
            VStack(alignment: .leading, spacing: 10) {
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
                }

                // Duration controls (only show if animation is selected)
                if overlay.animation != nil && overlay.animation?.type != Project.Overlay.Animation.AnimationType.none {
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
                    }
                }
            }
        }
    }
}
