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
/// Plus section-level zoom controls for individual segments
struct ZoomControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @State private var isEnabled: Bool
    @State private var intensity: Double
    @State private var showInfo: Bool = false
    @State private var showSectionControls: Bool = false

    private let intensityRange: ClosedRange<Double> = 0...2
    private let intensityLabels = ["Subtle", "Normal", "Aggressive"]
    private let batchColumns = [GridItem(.adaptive(minimum: 86, maximum: 140), spacing: 8)]

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { showInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
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

            // Zoom toggle
            HStack {
                Toggle("Enable Auto-Zoom", isOn: $isEnabled)
                    .onChangeCompat(of: isEnabled) { newValue in
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

            Divider()

            // Section-level controls button
            Button(action: { showSectionControls.toggle() }) {
                HStack {
                    Label("Section Controls", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Image(systemName: showSectionControls ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Section-level zoom controls (expandable)
            if showSectionControls {
                sectionZoomControls
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
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
                ZoomStatItem(icon: "checkmark.circle.fill", label: "Status", value: "Active")
                Spacer()
                ZoomStatItem(icon: "slider.horizontal.3", label: "Intensity", value: intensityLabel)
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
    static func intensityFromConfig(_ config: Project.Timeline.ZoomConfiguration) -> Double {
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

    /// Section-level zoom controls view
    private var sectionZoomControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Section Zoom Controls")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(editor.project.timeline.segments.count) sections")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Configure zoom intensity for each timeline segment individually")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // List of segments with individual controls
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(editor.project.timeline.segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentZoomRow(
                            segment: segment,
                            index: index,
                            editor: editor
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            // Batch controls
            LazyVGrid(columns: batchColumns, alignment: .leading, spacing: 8) {
                Button("Enable All") {
                    Task {
                        await enableAllZoom()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Disable All") {
                    Task {
                        await disableAllZoom()
                    }
                }
                .buttonStyle(.bordered)

                Button("Reset to Defaults") {
                    Task {
                        await resetAllZoom()
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Enable zoom for all segments
    private func enableAllZoom() async {
        for segment in editor.project.timeline.segments {
            let config = Project.Timeline.ZoomConfiguration(
                enabled: true,
                intensity: intensityFromSliderValue()
            )
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
        }
    }

    /// Disable zoom for all segments
    private func disableAllZoom() async {
        for segment in editor.project.timeline.segments {
            await editor.updateSegmentZoom(segmentId: segment.id, configuration: .disabled)
        }
    }

    /// Reset all zoom to defaults
    private func resetAllZoom() async {
        for segment in editor.project.timeline.segments {
            // Remove custom configuration to revert to defaults
            await editor.removeSegmentZoom(segmentId: segment.id)
        }
    }
}

// MARK: - Preview

// Previews disabled due to lack of mock data support
// #Preview("Zoom Controls - Enabled") {
//     let editor = try! ProjectEditor.mockProject()
//     return ZoomControlsView(editor: editor)
//         .frame(width: 350)
//         .padding()
// }
//
// #Preview("Zoom Controls - Disabled") {
//     let editor = try! ProjectEditor.mockProject()
//     // Mock disabled state
//     return ZoomControlsView(editor: editor)
//         .frame(width: 350)
//         .padding()
// }
