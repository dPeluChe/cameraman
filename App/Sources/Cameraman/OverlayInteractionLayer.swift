import SwiftUI
import EngineKit

struct OverlayInteractionLayer: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    @Binding var selectedOverlayId: UUID?

    @State private var interactionStartTransform: Project.Overlay.Transform?
    @State private var draftTransform: Project.Overlay.Transform?
    @State private var lastDraftPush: Date = .distantPast
    private static let draftThrottle: TimeInterval = 1.0 / 30.0

    private var activeOverlays: [Project.Overlay] {
        let time = playerViewModel.currentTime
        return editor.project.overlays.filter { time >= $0.start && time <= $0.end }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedOverlayId = nil }

                ForEach(activeOverlays) { overlay in
                    overlayHandle(overlay, in: geometry.size)
                }
            }
            .coordinateSpace(name: "overlayCanvas")
        }
    }

    @ViewBuilder
    private func overlayHandle(_ overlay: Project.Overlay, in canvasSize: CGSize) -> some View {
        let isSelected = overlay.id == selectedOverlayId
        let transform = isSelected ? (draftTransform ?? overlay.transform) : overlay.transform
        let rect = viewRect(for: overlay, transform: transform, in: canvasSize)

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(0.0001),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 0, dash: [4, 3])
                )
                .background(Color.white.opacity(0.0001))
                .contentShape(Rectangle())

            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1, height: 14)
                    .offset(y: -rect.height / 2 - 7)

                interactionHandle(systemImage: "arrow.triangle.2.circlepath")
                    .offset(y: -rect.height / 2 - 18)
                    .gesture(rotationGesture(for: overlay, in: canvasSize))

                interactionHandle(systemImage: "arrow.up.left.and.arrow.down.right")
                    .offset(x: rect.width / 2, y: rect.height / 2)
                    .gesture(resizeGesture(for: overlay, in: canvasSize))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .rotationEffect(.degrees(transform.rotation))
        .position(x: rect.midX, y: rect.midY)
        .onHover { inside in
            if inside {
                isSelected ? NSCursor.openHand.set() : NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture {
            draftTransform = nil
            selectedOverlayId = overlay.id
        }
        .gesture(moveGesture(for: overlay, in: canvasSize))
    }

    private func interactionHandle(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 16, height: 16)
            .background(Circle().fill(.background))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .contentShape(Circle())
    }

    private func moveGesture(for overlay: Project.Overlay, in canvasSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named("overlayCanvas"))
            .onChanged { value in
                beginInteraction(with: overlay)
                let base = interactionStartTransform ?? overlay.transform
                let translation = OverlayCanvasGeometry.normalizedTranslation(value.translation, in: canvasSize)
                updateDraft(
                    Project.Overlay.Transform(
                        x: clamped(base.x + Double(translation.x)),
                        y: clamped(base.y + Double(translation.y)),
                        scale: base.scale,
                        rotation: base.rotation
                    ),
                    overlayId: overlay.id
                )
                NSCursor.closedHand.set()
            }
            .onEnded { _ in
                finishInteraction(for: overlay)
                NSCursor.openHand.set()
            }
    }

    private func resizeGesture(for overlay: Project.Overlay, in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("overlayCanvas"))
            .onChanged { value in
                beginInteraction(with: overlay)
                let base = interactionStartTransform ?? overlay.transform
                let center = OverlayCanvasGeometry.viewPoint(x: base.x, y: base.y, in: canvasSize)
                let initialDistance = distance(from: value.startLocation, to: center)
                guard initialDistance > 0 else { return }
                let ratio = distance(from: value.location, to: center) / initialDistance
                updateDraft(
                    Project.Overlay.Transform(
                        x: base.x,
                        y: base.y,
                        scale: min(8, max(0.1, base.scale * ratio)),
                        rotation: base.rotation
                    ),
                    overlayId: overlay.id
                )
            }
            .onEnded { _ in finishInteraction(for: overlay) }
    }

    private func rotationGesture(for overlay: Project.Overlay, in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("overlayCanvas"))
            .onChanged { value in
                beginInteraction(with: overlay)
                let base = interactionStartTransform ?? overlay.transform
                let center = OverlayCanvasGeometry.viewPoint(x: base.x, y: base.y, in: canvasSize)
                let startAngle = atan2(value.startLocation.y - center.y, value.startLocation.x - center.x)
                let currentAngle = atan2(value.location.y - center.y, value.location.x - center.x)
                let degrees = Double((currentAngle - startAngle) * 180 / .pi)
                updateDraft(
                    Project.Overlay.Transform(
                        x: base.x,
                        y: base.y,
                        scale: base.scale,
                        rotation: normalizedDegrees(base.rotation + degrees)
                    ),
                    overlayId: overlay.id
                )
            }
            .onEnded { _ in finishInteraction(for: overlay) }
    }

    private func beginInteraction(with overlay: Project.Overlay) {
        if interactionStartTransform == nil {
            interactionStartTransform = overlay.transform
            draftTransform = overlay.transform
            selectedOverlayId = overlay.id
        }
    }

    private func updateDraft(_ transform: Project.Overlay.Transform, overlayId: UUID) {
        draftTransform = transform
        let now = Date()
        guard now.timeIntervalSince(lastDraftPush) >= Self.draftThrottle else { return }
        lastDraftPush = now
        playerViewModel.previewOverlayDraft(transform, overlayId: overlayId)
    }

    private func finishInteraction(for overlay: Project.Overlay) {
        guard let final = draftTransform else {
            resetInteraction()
            return
        }
        playerViewModel.previewOverlayDraft(final, overlayId: overlay.id)
        Task {
            let result = await editor.updateOverlay(
                projectId: editor.project.projectId,
                overlayId: overlay.id,
                transform: final
            )
            if case .failure(let error) = result {
                LogError(.editor, "Direct overlay edit failed: \(error.localizedDescription)")
                playerViewModel.refreshPreview(with: editor.project)
            }
        }
        resetInteraction()
    }

    private func resetInteraction() {
        interactionStartTransform = nil
        draftTransform = nil
        lastDraftPush = .distantPast
    }

    private func viewRect(
        for overlay: Project.Overlay,
        transform: Project.Overlay.Transform,
        in canvasSize: CGSize
    ) -> CGRect {
        OverlayCanvasGeometry.viewRect(
            x: transform.x,
            y: transform.y,
            relativeSize: OverlayBaseSize.relativeSize(for: overlay.type),
            scale: transform.scale,
            in: canvasSize
        )
    }

    private func distance(from point: CGPoint, to center: CGPoint) -> Double {
        Double(hypot(point.x - center.x, point.y - center.y))
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}
