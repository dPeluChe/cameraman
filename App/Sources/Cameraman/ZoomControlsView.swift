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
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)

        // Section-level zoom controls (expandable)
        if showSectionControls {
            sectionZoomControls
                .padding()
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
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
    fileprivate static func intensityFromConfig(_ config: Project.Timeline.ZoomConfiguration) -> Double {
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
            HStack(spacing: 8) {
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

                Spacer()

                Button("Reset to Defaults") {
                    Task {
                        await resetAllZoom()
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
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

/// Row view for individual segment zoom configuration
private struct SegmentZoomRow: View {
    let segment: Project.Timeline.Segment
    let index: Int
    @ObservedObject var editor: ProjectEditor

    @State private var isEnabled: Bool
    @State private var intensity: Double

    private let intensityRange: ClosedRange<Double> = 0...2
    private let intensityLabels = ["Subtle", "Normal", "Aggressive"]

    init(segment: Project.Timeline.Segment, index: Int, editor: ProjectEditor) {
        self.segment = segment
        self.index = index
        self.editor = editor

        // Initialize state from segment's zoom configuration
        if let zoomConfig = segment.zoom {
            self._isEnabled = State(initialValue: zoomConfig.enabled)
            self._intensity = State(initialValue: ZoomControlsView.intensityFromConfig(zoomConfig))
        } else {
            self._isEnabled = State(initialValue: true) // Default enabled
            self._intensity = State(initialValue: 1.0) // Default normal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segment header
            HStack {
                // Segment number badge
                Text("#\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(4)

                // Segment duration
                Text(formatDuration(segment.timelineOut - segment.timelineIn))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Zoom enabled toggle
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, newValue in
                        Task {
                            await updateSegmentEnabled(newValue)
                        }
                    }
            }

            // Intensity controls (only when enabled)
            if isEnabled {
                HStack(spacing: 12) {
                    Text("Intensity:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Intensity picker
                    Picker("", selection: $intensity) {
                        Text("Subtle").tag(0.0)
                        Text("Normal").tag(1.0)
                        Text("Aggressive").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: intensity) { _, _ in
                        Task {
                            await updateSegmentIntensity()
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }

    /// Format duration as time string
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)

        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%02ds", seconds, milliseconds)
        }
    }

    /// Update segment zoom enabled state
    private func updateSegmentEnabled(_ enabled: Bool) async {
        let config: Project.Timeline.ZoomConfiguration
        if enabled {
            config = Project.Timeline.ZoomConfiguration(
                enabled: true,
                intensity: intensityFromSliderValue()
            )
        } else {
            config = .disabled
        }
        await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
    }

    /// Update segment zoom intensity
    private func updateSegmentIntensity() async {
        let newIntensity = intensityFromSliderValue()
        let config = Project.Timeline.ZoomConfiguration(
            enabled: true,
            intensity: newIntensity
        )
        await editor.updateSegmentZoom(segmentId: segment.id, configuration: config)
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
