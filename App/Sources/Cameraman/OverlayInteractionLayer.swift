//
//  OverlayInteractionLayer.swift
//  App
//
//  Transparent hit-test + drag layer rendered on top of the AVPlayerLayerView.
//  Lets the user select an overlay by tapping inside its rect, and drag the
//  selected overlay to reposition it. Spatial feedback flows through
//  PreviewPlayerViewModel.previewOverlayDraft so the AVPlayer reflects the
//  motion live (bypassing editor.project debounce); commitOverlayPosition
//  fires on gesture end with the official editor.updateOverlay call (records
//  undo + autosave).
//

import SwiftUI
import EngineKit

struct OverlayInteractionLayer: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    @Binding var selectedOverlayId: UUID?

    @State private var dragStartTransform: Project.Overlay.Transform?
    @State private var dragStartProject: Project?
    @State private var draftTransform: Project.Overlay.Transform?
    @State private var lastDraftPush: Date = .distantPast
    private static let draftThrottle: TimeInterval = 1.0 / 30.0

    /// Overlays visible at the current playhead — only these are interactive.
    private var activeOverlays: [Project.Overlay] {
        let t = playerViewModel.currentTime
        return editor.project.overlays.filter { t >= $0.start && t <= $0.end }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(activeOverlays) { overlay in
                    let rect = self.rect(for: overlay, in: size)
                    let isSelected = overlay.id == selectedOverlayId
                    overlayHandle(overlay: overlay, rect: rect, isSelected: isSelected, in: size)
                }
            }
            .contentShape(Rectangle())
            // Tapping empty space clears the selection.
            .onTapGesture {
                selectedOverlayId = nil
            }
        }
    }

    @ViewBuilder
    private func overlayHandle(
        overlay: Project.Overlay,
        rect: CGRect,
        isSelected: Bool,
        in size: CGSize
    ) -> some View {
        let displayRect = isSelected && draftTransform != nil
            ? self.rect(for: overlay, in: size, overrideTransform: draftTransform)
            : rect

        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.white.opacity(0.0001),
                style: StrokeStyle(lineWidth: isSelected ? 2 : 0, dash: [4, 3])
            )
            .background(
                // Invisible-but-hittable fill; the dash border above only renders when selected.
                Color.white.opacity(0.0001)
            )
            .frame(width: displayRect.width, height: displayRect.height)
            .position(x: displayRect.midX, y: displayRect.midY)
            .onTapGesture {
                selectedOverlayId = overlay.id
            }
            .gesture(isSelected ? dragGesture(for: overlay, in: size) : nil)
    }

    private func dragGesture(for overlay: Project.Overlay, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTransform == nil {
                    dragStartTransform = overlay.transform
                    dragStartProject = editor.project
                }
                let base = dragStartTransform ?? overlay.transform
                let dx = Double(value.translation.width) / Double(size.width)
                let dy = Double(value.translation.height) / Double(size.height)
                // transform.y is stored in renderer convention (Y inverted from
                // SwiftUI's top-left). User drags DOWN in SwiftUI (dy positive),
                // which should DECREASE the stored y (toward 0 = bottom of
                // canvas in renderer space).
                let next = Project.Overlay.Transform(
                    x: max(0, min(1, base.x + dx)),
                    y: max(0, min(1, base.y - dy)),
                    scale: base.scale,
                    rotation: base.rotation
                )
                draftTransform = next
                pushDraftIfNeeded(overlayId: overlay.id, transform: next)
            }
            .onEnded { _ in
                let final = draftTransform ?? overlay.transform
                let snapshot = dragStartProject
                Task {
                    _ = await editor.updateOverlay(
                        projectId: editor.project.projectId,
                        overlayId: overlay.id,
                        transform: final,
                        style: nil,
                        start: nil,
                        end: nil,
                        animation: nil
                    )
                    _ = snapshot
                }
                dragStartTransform = nil
                dragStartProject = nil
                draftTransform = nil
            }
    }

    private func pushDraftIfNeeded(overlayId: UUID, transform: Project.Overlay.Transform) {
        let now = Date()
        guard now.timeIntervalSince(lastDraftPush) >= Self.draftThrottle else { return }
        lastDraftPush = now
        playerViewModel.previewOverlayDraft(transform, overlayId: overlayId)
    }

    /// Compute the rendered rect for an overlay within the preview canvas,
    /// matching OverlayBaseSize.relativeSize + the renderer's Y-flip convention
    /// inverted (we operate in SwiftUI top-left coordinates here).
    private func rect(
        for overlay: Project.Overlay,
        in size: CGSize,
        overrideTransform: Project.Overlay.Transform? = nil
    ) -> CGRect {
        let transform = overrideTransform ?? overlay.transform
        let relSize = OverlayBaseSize.relativeSize(for: overlay.type)
        let w = relSize.width * size.width * transform.scale
        let h = relSize.height * size.height * transform.scale
        // SwiftUI uses top-left origin; transform.y is stored in the renderer's
        // (1.0 - y) convention so we invert here to match what's painted.
        let cx = transform.x * size.width
        let cy = (1.0 - transform.y) * size.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
}
