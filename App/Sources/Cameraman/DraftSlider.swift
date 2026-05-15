//
//  DraftSlider.swift
//  App
//
//  Reusable slider that holds the in-progress value in local @State during a
//  drag and only commits via callback on `.onEditingChanged: false`. Eliminates
//  the "60 Tasks per second of drag" pattern that was happening in the overlay
//  popover where every slider tick fired a Task { await editor.updateOverlay }.
//
//  Use this anywhere a Slider drives an async mutation that hops through an
//  actor / autosave / debounce chain.
//

import SwiftUI

struct DraftSlider: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double?
    /// Live value when the slider is idle. While dragging, the slider reads
    /// from local draft state to avoid rubber-banding if `current` lags.
    let current: Double
    /// Formats `current` (or the draft while dragging) for the right-side
    /// label. Caller controls units (%, s, °, pt, etc).
    let display: (Double) -> String
    /// Called once when the drag ends with the final value.
    let commit: (Double) -> Void

    @State private var draft: Double?

    private var liveValue: Double { draft ?? current }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Group {
                if let step {
                    Slider(
                        value: sliderBinding(),
                        in: range,
                        step: step,
                        onEditingChanged: handleEditingChanged(_:)
                    )
                } else {
                    Slider(
                        value: sliderBinding(),
                        in: range,
                        onEditingChanged: handleEditingChanged(_:)
                    )
                }
            }
            .controlSize(.small)

            Text(display(liveValue))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func sliderBinding() -> Binding<Double> {
        Binding(
            get: { liveValue },
            set: { val in draft = val }
        )
    }

    private func handleEditingChanged(_ editing: Bool) {
        if !editing, let val = draft {
            commit(val)
            draft = nil
        }
    }
}
