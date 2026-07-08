//
//  ManualZoomControlsView.swift
//  App
//
//  Panel for adding/editing/removing manual zoom keyframes.
//

import SwiftUI
import Combine
import EngineKit

struct ManualZoomControlsView: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel

    @State private var selectedKeyframeId: UUID?
    @State private var isClickToFocusEnabled: Bool = false

    /// Shared state — set by the panel toggle, read by the preview overlay.
    /// Uses a static holder so the PreviewPlayerView can access it without
    /// a binding chain through the view hierarchy.
    static let clickToFocus = ClickToFocusState()

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

            // Click-to-focus toggle
            Toggle("Click preview to set focus", isOn: $isClickToFocusEnabled)
                .onChangeCompat(of: isClickToFocusEnabled) { v in
                    ManualZoomControlsView.clickToFocus.isEnabled = v
                    ManualZoomControlsView.clickToFocus.selectedKeyframeId = selectedKeyframeId
                    ManualZoomControlsView.clickToFocus.editor = editor
                    ManualZoomControlsView.clickToFocus.playerViewModel = playerViewModel
                }
                .font(.caption)
                .tint(.orange)

            if isClickToFocusEnabled {
                Text("Click anywhere on the preview to set the focus point of the selected keyframe (or create a new one at playhead).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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
        .onTapGesture { 
            selectedKeyframeId = isSelected ? nil : kf.id
            ManualZoomControlsView.clickToFocus.selectedKeyframeId = selectedKeyframeId
        }
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
            zoomLevel: 2.0,
            focusX: 0.5,
            focusY: 0.5,
            easing: .easeInOut
        )
        await playerViewModel.applyEffectiveZoomPlan()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", mins, secs)
    }
}

/// Shared state for click-to-focus mode. The panel sets it, the preview
/// overlay reads it. Uses a class so it can be referenced statically
/// without a binding chain.
final class ClickToFocusState: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var selectedKeyframeId: UUID?
    weak var editor: ProjectEditor?
    weak var playerViewModel: PreviewPlayerViewModel?

    func handleTap(_ point: CGPoint) {
        guard isEnabled else { return }
        guard let editor = editor else { return }

        if let selId = selectedKeyframeId {
            // Update existing keyframe's focus
            Task {
                await editor.updateManualZoomKeyframe(id: selId, focusX: point.x, focusY: point.y)
                await playerViewModel?.applyEffectiveZoomPlan()
            }
        } else {
            // Create new keyframe at playhead with this focus
            Task { @MainActor in
                let t = playerViewModel?.currentTime ?? 0
                await editor.addManualZoomKeyframe(
                    at: t,
                    zoomLevel: 2.0,
                    focusX: point.x,
                    focusY: point.y
                )
                await playerViewModel?.applyEffectiveZoomPlan()
            }
        }
    }
}
