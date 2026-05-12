//
//  ZoomControlsView+Subviews.swift
//  App
//
//  Extracted from ZoomControlsView.swift
//  Supporting subviews for zoom controls
//

import SwiftUI
import EngineKit

/// Stat item for zoom statistics
struct ZoomStatItem: View {
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
struct SegmentZoomRow: View {
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
                    .onChangeCompat(of: isEnabled) { newValue in
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
                    .onChangeCompat(of: intensity) { _ in
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
