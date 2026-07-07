//
//  ManualZoomControlsView.swift
//  App
//
//  Panel for adding/editing/removing manual zoom keyframes.
//

import SwiftUI
import EngineKit

struct ManualZoomControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel

    @State private var selectedKeyframeId: UUID?
    @State private var newZoomLevel: Double = 2.0
    @State private var newFocusX: Double = 0.5
    @State private var newFocusY: Double = 0.5
    @State private var newEasing: ZoomPlanGenerator.EasingFunction = .easeInOut
    @State private var showAddSheet: Bool = false

    private var manualKeyframes: [ZoomPlanGenerator.ZoomKeyframe] {
        editor.project.manualZoomKeyframes ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manual Zoom")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !manualKeyframes.isEmpty {
                    Button(action: { Task { await editor.clearAllManualZoomKeyframes() } }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Add zoom in/out keyframes at specific timestamps to highlight areas. Merges with auto-zoom.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add keyframe at playhead
            Button {
                Task { await addKeyframeAtPlayhead() }
            } label: {
                Label("Add at Playhead", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // Keyframe list
            if !manualKeyframes.isEmpty {
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manualKeyframes) { kf in
                            keyframeRow(kf)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            // Selected keyframe editor
            if let selected = manualKeyframes.first(where: { $0.id == selectedKeyframeId }) {
                Divider()
                keyframeEditor(selected)
            }
        }
    }

    private func keyframeRow(_ kf: ZoomPlanGenerator.ZoomKeyframe) -> some View {
        let isSelected = kf.id == selectedKeyframeId
        return HStack(spacing: 8) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.orange.opacity(0.6))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(kf.timestamp))
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(String(format: "%.1f", kf.zoomLevel))x at (\(String(format: "%.0f", kf.focusX * 100))%, \(String(format: "%.0f", kf.focusY * 100))%)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { Task { await editor.removeManualZoomKeyframe(id: kf.id) } }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { selectedKeyframeId = isSelected ? nil : kf.id }
    }

    private func keyframeEditor(_ kf: ZoomPlanGenerator.ZoomKeyframe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Keyframe")
                .font(.caption)
                .fontWeight(.semibold)

            // Zoom level slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Zoom Level")
                        .font(.caption2)
                    Spacer()
                    Text("\(String(format: "%.1f", kf.zoomLevel))x")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                Slider(value: Binding(
                    get: { kf.zoomLevel },
                    set: { v in
                        Task { await editor.updateManualZoomKeyframe(id: kf.id, zoomLevel: v) }
                    }
                ), in: 1.0...4.0, step: 0.1)
                .tint(.orange)
            }

            // Focus X slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Focus X")
                        .font(.caption2)
                    Spacer()
                    Text("\(String(format: "%.0f", kf.focusX * 100))%")
                        .font(.caption2)
                }
                Slider(value: Binding(
                    get: { kf.focusX },
                    set: { v in
                        Task { await editor.updateManualZoomKeyframe(id: kf.id, focusX: v) }
                    }
                ), in: 0.0...1.0, step: 0.01)
                .tint(.orange)
            }

            // Focus Y slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Focus Y")
                        .font(.caption2)
                    Spacer()
                    Text("\(String(format: "%.0f", kf.focusY * 100))%")
                        .font(.caption2)
                }
                Slider(value: Binding(
                    get: { kf.focusY },
                    set: { v in
                        Task { await editor.updateManualZoomKeyframe(id: kf.id, focusY: v) }
                    }
                ), in: 0.0...1.0, step: 0.01)
                .tint(.orange)
            }

            // Easing picker
            HStack {
                Text("Easing")
                    .font(.caption2)
                Spacer()
                Picker("", selection: Binding(
                    get: { kf.easing },
                    set: { e in
                        Task { await editor.updateManualZoomKeyframe(id: kf.id, easing: e) }
                    }
                )) {
                    Text("Linear").tag(ZoomPlanGenerator.EasingFunction.linear)
                    Text("Ease In").tag(ZoomPlanGenerator.EasingFunction.easeIn)
                    Text("Ease Out").tag(ZoomPlanGenerator.EasingFunction.easeOut)
                    Text("Ease In-Out").tag(ZoomPlanGenerator.EasingFunction.easeInOut)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func addKeyframeAtPlayhead() async {
        let t = playerViewModel.currentTime
        await editor.addManualZoomKeyframe(
            at: t,
            zoomLevel: newZoomLevel,
            focusX: newFocusX,
            focusY: newFocusY,
            easing: newEasing
        )
        await playerViewModel.applyEffectiveZoomPlan()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", mins, secs)
    }
}
