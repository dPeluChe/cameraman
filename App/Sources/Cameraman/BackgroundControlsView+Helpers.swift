//
//  BackgroundControlsView+Helpers.swift
//  App
//
//  Extracted from BackgroundControlsView.swift
//  Helper views, buttons, and Color extensions for background controls
//

import SwiftUI
import AppKit
import EngineKit

// MARK: - Background Type Button

struct BackgroundTypeButton: View {
    let type: CanvasLayout.BackgroundType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.backgroundIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Text(type.backgroundDisplayName)
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

// MARK: - Image Fit Mode Button

struct FitModeButton: View {
    let mode: CanvasLayout.ImageFitMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.fitModeIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Text(mode.fitModeShortName)
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

// MARK: - Color Picker View

struct BackgroundColorPickerView: View {
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

// MARK: - CanvasLayout Extensions

extension CanvasLayout.BackgroundType {
    var backgroundIcon: String {
        switch self {
        case .solid:
            return "paintpalette"
        case .image:
            return "photo"
        case .blur:
            return "camera.filters"
        }
    }

    var backgroundDisplayName: String {
        displayName
    }
}

extension CanvasLayout.ImageFitMode {
    var fitModeIcon: String {
        switch self {
        case .fit:
            return "rectangle.compress.vertical"
        case .fill:
            return "rectangle.expand.vertical"
        }
    }

    var fitModeShortName: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        }
    }
}

// MARK: - Color Extensions

extension Color {
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

        let luminance = (0.299 * r + 0.587 * g + 0.114 * b)

        return luminance < 0.5
    }
}
