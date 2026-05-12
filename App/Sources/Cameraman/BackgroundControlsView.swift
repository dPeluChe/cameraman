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
    private let quickColorColumns = [GridItem(.adaptive(minimum: 22, maximum: 24), spacing: 4)]
    private let fitModeColumns = [GridItem(.adaptive(minimum: 74, maximum: 120), spacing: 8)]
    private let gradientColumns = [GridItem(.adaptive(minimum: 52, maximum: 72), spacing: 8)]

    private var background: Project.Canvas.Background {
        editor.project.canvas.background
    }

    private var backgroundType: CanvasLayout.BackgroundType {
        CanvasLayout.BackgroundType(rawValue: background.type) ?? .solid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Background type selector
            HStack(spacing: 8) {
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
            case .gradient:
                gradientControls
            }
        }
    }

    @ViewBuilder
    private var solidColorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Color preview button
            Button {
                colorPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selectedColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )

                    Text(background.value.isEmpty ? "Pick Color" : background.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "eyedropper")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Quick color presets (wrapped grid)
            LazyVGrid(columns: quickColorColumns, alignment: .leading, spacing: 4) {
                ForEach(quickColors, id: \.self) { hex in
                    Button {
                        Task {
                            await editor.updateBackgroundColor(hex)
                            updateSelectedColor()
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
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
            BackgroundColorPickerView(
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
            Task { @MainActor in updateSelectedColor() }
        }
        .onChangeCompat(of: background.value) { _ in
            Task { @MainActor in updateSelectedColor() }
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

                    LazyVGrid(columns: fitModeColumns, alignment: .leading, spacing: 8) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var gradientControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gradient Presets")
                .font(.subheadline)

            LazyVGrid(columns: gradientColumns, alignment: .leading, spacing: 8) {
                ForEach(CanvasLayout.GradientPreset.allCases, id: \.self) { preset in
                    let parts = preset.rawValue.split(separator: ",")
                    let isSelected = background.value == preset.rawValue

                    Button {
                        Task {
                            var updatedProject = editor.project
                            updatedProject.canvas.background = CanvasLayout.createGradientBackground(preset: preset)
                            await editor.setProject(updatedProject)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    colors: [
                                        Color(hex: String(parts.first ?? "#000")),
                                        Color(hex: String(parts.dropFirst().first ?? "#333"))
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                )

                            Text(preset.displayName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
