//
//  OverlayPopover.swift
//  App
//
//  Popover for editing overlay properties.
//  Appears on second click of an overlay in the timeline.
//

import AppKit
import SwiftUI
import EngineKit
import UniformTypeIdentifiers

struct OverlayPopoverContent: View {
    @ObservedObject var editor: ProjectEditor
    let overlayId: UUID

    /// In-progress slider value while the user is dragging Start/End. While
    /// non-nil it takes precedence over `overlay.start` / `overlay.end` so the
    /// slider doesn't rubber-band when the async `editor.updateOverlay` hasn't
    /// propagated yet.
    /// Internal access (not private) so OverlayPopover+Sections.swift can read.
    @State var draftStart: Double?
    @State var draftEnd: Double?

    private var overlay: Project.Overlay? {
        editor.project.overlays.first { $0.id == overlayId }
    }

    var body: some View {
        if let overlay {
            VStack(alignment: .leading, spacing: 0) {
                header(for: overlay)
                Divider()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        timingSection(overlay: overlay)
                        animationSection(overlay: overlay)
                        transformSection(overlay: overlay)
                        styleSection(overlay: overlay)
                        deleteButton
                    }
                    .padding(16)
                }
            }
            .frame(width: 280)
            .frame(maxHeight: 540)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(for overlay: Project.Overlay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                .font(.system(size: 16))
                .foregroundStyle(.cyan)
            Text(OverlayDisplayInfo.label(for: overlay.type))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(String(format: "%.2fs", overlay.end - overlay.start))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.08))
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // Sections / labeledSlider / popoverSection / smallLabeled / fadeBinding /
    // presentChangeImagePanel moved to OverlayPopover+Sections.swift.

    // MARK: - Helpers (internal so OverlayPopover+Sections.swift extension can call them)

    func mutate(_ overlay: Project.Overlay, _ block: (inout Project.Overlay) -> Void) {
        var updated = overlay
        block(&updated)
        Task {
            _ = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlayId,
                transform: updated.transform,
                style: updated.style
            )
        }
    }

    func sliderBinding(_ overlay: Project.Overlay, _ kp: WritableKeyPath<Project.Overlay, Double>) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: kp] },
            set: { val in mutate(overlay) { $0[keyPath: kp] = val } }
        )
    }

    func optionalSliderBinding(_ overlay: Project.Overlay, _ kp: WritableKeyPath<Project.Overlay, Double?>, default defaultVal: Double) -> Binding<Double> {
        Binding(
            get: { overlay[keyPath: kp] ?? defaultVal },
            set: { val in mutate(overlay) { $0[keyPath: kp] = val } }
        )
    }

    /// Timing binding for Start/End sliders. While the user is dragging the
    /// slider, the value lives in `draftStart` / `draftEnd` local state — we
    /// only commit to `editor.updateOverlay` when the gesture ends. Avoids
    /// rubber-banding while the async update propagates back through
    /// `editor.$project` and avoids 60 concurrent Tasks per drag.
    func timingBinding(_ overlay: Project.Overlay, isStart: Bool, maxDuration: TimeInterval) -> Binding<Double> {
        Binding(
            get: {
                if isStart {
                    return draftStart ?? overlay.start
                } else {
                    return draftEnd ?? overlay.end
                }
            },
            set: { val in
                if isStart {
                    draftStart = max(0, min(val, overlay.end - 0.1))
                } else {
                    draftEnd = max(overlay.start + 0.1, min(val, maxDuration))
                }
            }
        )
    }

    func commitTiming(isStart: Bool, overlay: Project.Overlay) {
        if isStart {
            guard let val = draftStart else { return }
            draftStart = nil
            Task {
                _ = await editor.updateOverlay(
                    projectId: editor.project.projectId,
                    overlayId: overlayId,
                    start: val
                )
            }
        } else {
            guard let val = draftEnd else { return }
            draftEnd = nil
            Task {
                _ = await editor.updateOverlay(
                    projectId: editor.project.projectId,
                    overlayId: overlayId,
                    end: val
                )
            }
        }
    }

    func hexString(from color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// PositionPreset + OverlayPositionCanvas moved to OverlayPositionCanvas.swift
