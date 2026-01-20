//
//  ZoomControlsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20
//  Épica UI-J — Zoom Controls (P1)
//

import SwiftUI
import EngineKit

/// Zoom controls UI for managing auto-zoom behavior
/// Provides toggle and intensity slider for global zoom configuration
struct ZoomControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var isEnabled: Bool
    @State private var intensity: Double
    @State private var showInfo: Bool = false

    private let intensityRange: ClosedRange<Double> = 0...2
    private let intensityLabels = ["Subtle", "Normal", "Aggressive"]

    init(editor: ProjectEditor) {
        self.editor = editor
        // Initialize state from project settings
        // Check first segment's zoom config as indicator of global state
        if let firstSegment = editor.project.timeline.segments.first,
           let zoomConfig = firstSegment.zoom {
            self._isEnabled = State(initialValue: zoomConfig.enabled)
            self._intensity = State(initialValue: ZoomControlsView.intensityFromConfig(zoomConfig))
        } else {
            self._isEnabled = State(initialValue: true) // Default enabled
            self._intensity = State(initialValue: 1.0) // Default normal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Auto-Zoom", systemImage: "magnifyingglass.plus")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Info button
                Button(action: { showInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Auto-Zoom")
                            .font(.headline)
                        Text("Auto-zoom automatically zooms in on important areas during cursor clicks and interactions.")
                            .font(.body)
                        Text("• Subtle: Minimal zoom, slower transitions")
                        Text("• Normal: Balanced zoom (recommended)")
                        Text("• Aggressive: Strong zoom, faster transitions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(width: 250)
                }
            }

            Divider()

            // Zoom toggle
            HStack {
                Toggle("Enable Auto-Zoom", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        Task {
                            await updateZoomEnabled(newValue)
                        }
                    }

                Spacer()

                // Status indicator
                Circle()
                    .fill(isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            // Intensity slider (only shown when zoom is enabled)
            if isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    // Intensity label with current value
                    HStack {
                        Text("Intensity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(intensityLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }

                    // Intensity slider
                    HStack(spacing: 12) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Slider(
                            value: $intensity,
                            in: intensityRange,
                            step: 1
                        ) {
                            Text("Zoom Intensity")
                        } onEditingChanged: { editing in
                            if !editing {
                                Task {
                                    await updateZoomIntensity()
                                }
                            }
                        }
                        .tint(.accentColor)

                        Image(systemName: "plus.magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    // Intensity markers
                    HStack {
                        ForEach(0..<intensityLabels.count, id: \.self) { index in
                            if index == 0 {
                                Text(intensityLabels[index])
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if index == intensityLabels.count - 1 {
                                Spacer()
                                Text(intensityLabels[index])
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Spacer()
                                Text(intensityLabels[index])
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if index < intensityLabels.count - 1 {
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Statistics (if zoom has been applied)
            if isEnabled {
                zoomStatistics
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    /// Zoom statistics view
    private var zoomStatistics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zoom Settings Applied")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            HStack {
                StatItem(icon: "checkmark.circle.fill", label: "Status", value: "Active")
                Spacer()
                StatItem(icon: "slider.horizontal.3", label: "Intensity", value: intensityLabel)
            }
            .font(.caption)
        }
        .padding(.top, 8)
    }

    /// Current intensity label
    private var intensityLabel: String {
        switch intensity {
        case 0:
            return "Subtle"
        case 1:
            return "Normal"
        case 2:
            return "Aggressive"
        default:
            return "Normal"
        }
    }

    /// Update zoom enabled state for all segments
    private func updateZoomEnabled(_ enabled: Bool) async {
        for segment in editor.project.timeline.segments {
            let config: Project.Timeline.ZoomConfiguration
            if enabled {
                // Use current intensity
                config = Project.Timeline.ZoomConfiguration(
                    enabled: true,
                    intensity: intensityFromSliderValue()
                )
            } else {
                config = .disabled
            }
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
        }
    }

    /// Update zoom intensity for all segments
    private func updateZoomIntensity() async {
        let newIntensity = intensityFromSliderValue()
        for segment in editor.project.timeline.segments {
            // Only update segments where zoom is enabled
            if segment.zoom?.enabled ?? true {
                let config = Project.Timeline.ZoomConfiguration(
                    enabled: true,
                    intensity: newIntensity
                )
                await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
            }
        }
    }

    /// Convert slider intensity value to ZoomIntensity enum
    private func intensityFromSliderValue() -> Project.Timeline.ZoomConfiguration.ZoomIntensity {
        switch Int(intensity) {
        case 0:
            return .subtle
        case 1:
            return .normal
        case 2:
            return .aggressive
        default:
            return .normal
        }
    }

    /// Convert ZoomConfiguration to slider intensity value
    private static func intensityFromConfig(_ config: Project.Timeline.ZoomConfiguration) -> Double {
        guard let intensity = config.intensity else {
            return 1.0 // Default to normal
        }
        switch intensity {
        case .disabled:
            return 1.0
        case .subtle:
            return 0.0
        case .normal:
            return 1.0
        case .aggressive:
            return 2.0
        }
    }
}

/// Stat item for zoom statistics
private struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text("\(label):")
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview("Zoom Controls - Enabled") {
    let editor = try! ProjectEditor.mockProject()
    return ZoomControlsView(editor: editor)
        .frame(width: 350)
        .padding()
}

#Preview("Zoom Controls - Disabled") {
    let editor = try! ProjectEditor.mockProject()
    // Mock disabled state
    return ZoomControlsView(editor: editor)
        .frame(width: 350)
        .padding()
}
