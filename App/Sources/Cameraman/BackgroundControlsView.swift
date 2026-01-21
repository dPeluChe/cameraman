//
//  BackgroundControlsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import UniformTypeIdentifiers
import EngineKit
import AppKit

/// Background configuration view with color picker, image selector, and fit mode
struct BackgroundControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var showImagePicker = false
    @State private var selectedColor: Color = .black
    @State private var colorPickerPresented = false

    private var background: Project.Canvas.Background {
        editor.project.canvas.background
    }

    private var backgroundType: CanvasLayout.BackgroundType {
        CanvasLayout.BackgroundType(rawValue: background.type) ?? .solid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Background")
                .font(.headline)

            // Background type selector
            HStack(spacing: 12) {
                ForEach(CanvasLayout.BackgroundType.allCases, id: \.self) { type in
                    BackgroundTypeButton(
                        type: type,
                        isSelected: backgroundType == type
                    ) {
                        Task {
                            await editor.setBackgroundType(type)
                            updateSelectedColor()
                        }
                    }
                }
            }

            // Type-specific controls
            switch backgroundType {
            case .solid:
                solidColorControls
            case .image:
                imageControls
            case .blur:
                blurControls
            }
        }
    }

    @ViewBuilder
    private var solidColorControls: some View {
        HStack(spacing: 12) {
            // Color preview button
            Button {
                colorPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(selectedColor)
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )

                        Image(systemName: "eyedropper")
                            .font(.caption)
                            .foregroundStyle(
                                selectedColor.isDark ? .white : .primary
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }

                    Text(background.value.isEmpty ? "Pick Color" : background.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Quick color presets
            HStack(spacing: 6) {
                ForEach(quickColors, id: \.self) { hex in
                    Button {
                        Task {
                            await editor.updateBackgroundColor(hex)
                            updateSelectedColor()
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $colorPickerPresented) {
            ColorPickerView(
                selectedColor: $selectedColor,
                onColorSelected: { hex in
                    Task {
                        await editor.updateBackgroundColor(hex)
                        updateSelectedColor()
                    }
                }
            )
        }
        .onAppear {
            updateSelectedColor()
        }
        .onChange(of: background.value) { _, _ in
            updateSelectedColor()
        }
    }

    @ViewBuilder
    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image path display and picker button
            HStack(spacing: 8) {
                if background.value.isEmpty {
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Choose Image...", systemImage: "photo")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)

                        Text((background.value as NSString).lastPathComponent)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            showImagePicker = true
                        } label: {
                            Text("Change")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                await editor.updateBackgroundImagePath("")
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .fileImporter(
                isPresented: $showImagePicker,
                allowedContentTypes: [.image],
                onCompletion: { result in
                    switch result {
                    case .success(let url):
                        Task {
                            await editor.updateBackgroundImagePath(url.path)
                        }
                    case .failure:
                        break
                    }
                }
            )

            // Fit mode selector
            if !background.value.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fit Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(CanvasLayout.ImageFitMode.allCases, id: \.self) { mode in
                            FitModeButton(
                                mode: mode,
                                isSelected: background.fitMode == mode.rawValue
                            ) {
                                Task {
                                    await editor.updateBackgroundFitMode(mode)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var blurControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blur Radius")
                .font(.subheadline)

            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: {
                            Double(background.value) ?? 10.0
                        },
                        set: { newValue in
                            Task {
                                let newBackground = Project.Canvas.Background(
                                    type: background.type,
                                    value: String(format: "%.0f", newValue),
                                    fitMode: background.fitMode
                                )
                                await editor.updateBackground(newBackground)
                            }
                        }
                    ),
                    in: 0...100,
                    step: 1
                )

                Text("\(Int(Double(background.value) ?? 10.0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            Text("Applies a blur effect to the screen content")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var quickColors: [String] {
        [
            "#0B0B0D", // Default dark
            "#FFFFFF", // White
            "#1A1A1E", // Dark gray
            "#2C2C2E", // Medium gray
            "#007AFF", // Blue
            "#5856D6", // Purple
            "#FF3B30", // Red
            "#FF9500", // Orange
            "#FFCC00", // Yellow
            "#34C759", // Green
        ]
    }

    private func updateSelectedColor() {
        selectedColor = Color(hex: background.value.isEmpty ? "#0B0B0D" : background.value)
    }
}

/// Background type selector button
private struct BackgroundTypeButton: View {
    let type: CanvasLayout.BackgroundType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Text(type.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Image fit mode selector button
private struct FitModeButton: View {
    let mode: CanvasLayout.ImageFitMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Text(mode.shortName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// System color picker wrapper
private struct ColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedColor: Color
    let onColorSelected: (String) -> Void

    @State private var tempColor: Color

    init(selectedColor: Binding<Color>, onColorSelected: @escaping (String) -> Void) {
        self._selectedColor = selectedColor
        self._tempColor = State(initialValue: selectedColor.wrappedValue)
        self.onColorSelected = onColorSelected
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Background Color")
                .font(.headline)
                .padding(.top)

            ColorPicker("Color", selection: $tempColor)
                .labelsHidden()
                .frame(height: 100)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Select") {
                    selectedColor = tempColor
                    if let hex = tempColor.toHex() {
                        onColorSelected(hex)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .frame(width: 300, height: 200)
        .padding()
    }
}

// MARK: - Extensions

private extension CanvasLayout.BackgroundType {
    var icon: String {
        switch self {
        case .solid:
            return "paintpalette"
        case .image:
            return "photo"
        case .blur:
            return "camera.filters"
        }
    }
}

private extension CanvasLayout.ImageFitMode {
    var icon: String {
        switch self {
        case .fit:
            return "rectangle.compress.vertical"
        case .fill:
            return "rectangle.expand.vertical"
        }
    }

    var shortName: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = components.count >= 4 ? Float(components[3]) : 1.0

        if a == 1.0 {
            return String(format: "#%02lX%02lX%02lX",
                         lroundf(r * 255),
                         lroundf(g * 255),
                         lroundf(b * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX%02lX",
                         lroundf(r * 255),
                         lroundf(g * 255),
                         lroundf(b * 255),
                         lroundf(a * 255))
        }
    }

    var isDark: Bool {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return false
        }

        let r = components[0]
        let g = components[1]
        let b = components[2]

        // Calculate luminance
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b)

        return luminance < 0.5
    }
}
