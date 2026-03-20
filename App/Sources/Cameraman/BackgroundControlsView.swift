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

