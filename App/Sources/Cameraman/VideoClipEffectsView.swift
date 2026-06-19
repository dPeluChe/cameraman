//
//  VideoClipEffectsView.swift
//  App
//
//  Per-clip effects panel for a selected imported-video clip: add/remove color
//  filters, blur and audio pitch, with a slider for parameterized kinds. Drives
//  the EngineKit Adjustment system (rendered by the overlay compositor).
//

import SwiftUI
import EngineKit

struct VideoClipEffectsView: View {
    @ObservedObject var editor: ProjectEditor
    let clipId: String
    let trackId: UUID

    struct Effect: Identifiable {
        let kind: Project.AdjustmentKind
        let label: String
        let param: Param?
        var id: String { kind.rawValue }
        struct Param { let key: String; let range: ClosedRange<Double>; let def: Double }
    }

    static let catalog: [Effect] = [
        Effect(kind: .sepia, label: "Sepia", param: .init(key: "intensity", range: 0...1, def: 1)),
        Effect(kind: .monochrome, label: "Black & White", param: nil),
        Effect(kind: .invert, label: "Invert", param: nil),
        Effect(kind: .vignette, label: "Vignette", param: .init(key: "intensity", range: 0...2, def: 1)),
        Effect(kind: .brightness, label: "Brightness", param: .init(key: "brightness", range: -0.5...0.5, def: 0)),
        Effect(kind: .contrast, label: "Contrast", param: .init(key: "contrast", range: 0.5...1.5, def: 1)),
        Effect(kind: .saturation, label: "Saturation", param: .init(key: "saturation", range: 0...2, def: 1)),
        Effect(kind: .gaussianBlur, label: "Blur", param: .init(key: "radius", range: 0...20, def: 8)),
        Effect(kind: .audioPitch, label: "Audio Pitch", param: .init(key: "cents", range: -1200...1200, def: 0))
    ]

    private var applied: [Project.Adjustment] {
        editor.project.timeline.tracks.first { $0.id == trackId }?
            .clips.first { $0.id == clipId }?.adjustments ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Effects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(Self.catalog) { effect in
                        Button(effect.label) { add(effect) }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }

            if applied.isEmpty {
                Text("No effects. Add color filters, blur or audio pitch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(applied, id: \.id) { adj in
                    effectRow(adj)
                }
            }
        }
    }

    @ViewBuilder
    private func effectRow(_ adj: Project.Adjustment) -> some View {
        let effect = Self.catalog.first { $0.kind.rawValue == adj.kind.rawValue }
        HStack(spacing: 6) {
            Text(effect?.label ?? adj.kind.rawValue)
                .font(.caption)
                .frame(width: 96, alignment: .leading)

            if let param = effect?.param {
                AdjustmentSlider(
                    value: adj.parameters[param.key] ?? param.def,
                    range: param.range
                ) { newValue in
                    commit(adj, key: param.key, value: newValue)
                }
            } else {
                Spacer()
            }

            Button {
                Task { _ = await editor.removeAdjustment(adj.id, fromClipId: clipId, inTrackId: trackId) }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func add(_ effect: Effect) {
        var params: [String: Double] = [:]
        if let p = effect.param { params[p.key] = p.def }
        let adj = Project.Adjustment(kind: effect.kind, target: .frame, parameters: params)
        Task { _ = await editor.addAdjustment(adj, toClipId: clipId, inTrackId: trackId) }
    }

    private func commit(_ adj: Project.Adjustment, key: String, value: Double) {
        var params = adj.parameters
        params[key] = value
        let updated = Project.Adjustment(
            id: adj.id, kind: adj.kind, target: adj.target,
            parameters: params, enabled: adj.enabled, start: adj.start, end: adj.end
        )
        Task { _ = await editor.updateAdjustment(updated, inClipId: clipId, trackId: trackId) }
    }
}

/// Slider that edits locally and commits once on release (avoids an undo entry
/// per drag tick).
private struct AdjustmentSlider: View {
    @State private var value: Double
    let range: ClosedRange<Double>
    let onCommit: (Double) -> Void

    init(value: Double, range: ClosedRange<Double>, onCommit: @escaping (Double) -> Void) {
        _value = State(initialValue: value)
        self.range = range
        self.onCommit = onCommit
    }

    var body: some View {
        Slider(value: $value, in: range) { editing in
            if !editing { onCommit(value) }
        }
        .controlSize(.mini)
    }
}
