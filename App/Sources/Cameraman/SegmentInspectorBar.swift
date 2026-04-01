//
//  SegmentInspectorBar.swift
//  App
//
//  Compact inspector bar shown below the timeline toolbar when a segment is selected.
//  Provides controls for per-segment speed and camera position.
//

import SwiftUI
import EngineKit

struct SegmentInspectorBar: View {
    let segment: Project.Timeline.Segment
    let projectCamera: Project.Canvas.Layout.CameraPosition?
    let onSpeedChange: (Double) -> Void
    let onCameraOverride: () -> Void
    let onCameraReset: () -> Void

    private let speedPresets: [Double] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]

    var body: some View {
        HStack(spacing: 16) {
            // Segment info
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1fs", segment.timelineDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 16)

            // Speed control
            HStack(spacing: 6) {
                Text("Speed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { closestPreset(to: segment.speed) },
                    set: { onSpeedChange($0) }
                )) {
                    ForEach(speedPresets, id: \.self) { speed in
                        Text(speedLabel(speed)).tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)
                .controlSize(.small)
            }

            Divider().frame(height: 16)

            // Camera position
            HStack(spacing: 6) {
                Text("Camera:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if segment.cameraPosition != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Custom")
                            .font(.caption)

                        Button {
                            onCameraReset()
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to project default camera position")
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("Default")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            onCameraOverride()
                        } label: {
                            Text("Customize")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(projectCamera == nil)
                        .help("Set a custom camera position for this segment")
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }

    private func closestPreset(to speed: Double) -> Double {
        speedPresets.min(by: { abs($0 - speed) < abs($1 - speed) }) ?? 1.0
    }

    private func speedLabel(_ speed: Double) -> String {
        if speed == 1.0 { return "1x" }
        if speed == 0.25 { return "0.25x" }
        if speed.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(speed))x"
        }
        return String(format: "%.1fx", speed)
    }
}
