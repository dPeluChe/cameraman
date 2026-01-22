//
//  ProjectEditorLayoutViews.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

// MARK: - LayoutSelectorView

struct LayoutSelectorView: View {
    @ObservedObject var editor: ProjectEditor

    private let presets: [CanvasLayout.LayoutPreset] = [.fullscreen, .pip, .sideBySide]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(presets, id: \.self) { preset in
                    LayoutPresetButton(
                        preset: preset,
                        isSelected: preset == selectedPreset,
                        isEnabled: isPresetEnabled(preset)
                    ) {
                        Task {
                            _ = await editor.setLayoutPreset(preset)
                        }
                    }
                }
            }
        }
    }

    private var selectedPreset: CanvasLayout.LayoutPreset {
        CanvasLayout.LayoutPreset(rawValue: editor.project.canvas.layout.type) ?? .fullscreen
    }

    private func isPresetEnabled(_ preset: CanvasLayout.LayoutPreset) -> Bool {
        preset == .fullscreen || editor.project.primarySources?.camera != nil
    }
}

struct LayoutPresetButton: View {
    let preset: CanvasLayout.LayoutPreset
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LayoutPreview(preset: preset)
                    .frame(width: 92, height: 56)

                Text(label)
                    .font(.subheadline)
            }
            .padding(10)
            .frame(minWidth: 110)
            .background(backgroundShape.fill(Color.primary.opacity(isSelected ? 0.12 : 0.04)))
            .overlay(
                backgroundShape.stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    private var label: String {
        switch preset {
        case .fullscreen:
            return "Full"
        case .pip:
            return "PiP"
        case .sideBySide:
            return "Side-by-Side"
        case .cinematic:
            return "Cinematic"
        }
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

struct LayoutPreview: View {
    let preset: CanvasLayout.LayoutPreset

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let canvas = RoundedRectangle(cornerRadius: 6, style: .continuous)
            let screenFill = Color.primary.opacity(0.16)
            let accentFill = Color.accentColor.opacity(0.55)

            ZStack {
                canvas.fill(Color.primary.opacity(0.04))
                canvas.stroke(Color.primary.opacity(0.2), lineWidth: 1)

                switch preset {
                case .fullscreen:
                    canvas.fill(screenFill).padding(3)
                case .pip:
                    canvas.fill(screenFill).padding(3)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accentFill)
                        .frame(width: size.width * 0.32, height: size.height * 0.32)
                        .position(x: size.width * 0.74, y: size.height * 0.74)
                case .sideBySide:
                    HStack(spacing: size.width * 0.04) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(screenFill)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accentFill)
                    }
                    .padding(4)
                case .cinematic:
                    canvas.fill(screenFill).padding(3)
                }
            }
        }
    }
}

// MARK: - FormatToggleView

struct FormatToggleView: View {
    @ObservedObject var editor: ProjectEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FormatButton(
                    title: "16:9",
                    icon: "rectangle.ratio.16.to.9",
                    isSelected: isAspect(.landscape16_9)
                ) {
                    setAspect(.landscape16_9)
                }

                FormatButton(
                    title: "9:16",
                    icon: "rectangle.ratio.9.to.16",
                    isSelected: isAspect(.portrait9_16)
                ) {
                    setAspect(.portrait9_16)
                }

                FormatButton(
                    title: "1:1",
                    icon: "square",
                    isSelected: isAspect(.square1_1)
                ) {
                    setAspect(.square1_1)
                }
            }
        }
    }

    private func isAspect(_ ratio: CanvasLayout.AspectRatio) -> Bool {
        return editor.project.canvas.format.aspect == ratio.rawValue
    }

    private func setAspect(_ ratio: CanvasLayout.AspectRatio) {
        Task {
            _ = await editor.setFormat(ratio)
        }
    }
}

struct FormatButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(width: 80, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
