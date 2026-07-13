import SwiftUI
import EngineKit

struct OverlayInteractionLayer: View {
    @ObservedObject var editor: ProjectEditor
    @ObservedObject var playerViewModel: PreviewPlayerViewModel
    @Binding var selectedOverlayId: UUID?

    @State private var interactionStartTransform: Project.Overlay.Transform?
    @State private var draftTransform: Project.Overlay.Transform?
    @State private var lastDraftPush: Date = .distantPast
    @State private var verticalGuide: CGFloat?
    @State private var horizontalGuide: CGFloat?
    @State private var keyboardCommitTask: Task<Void, Never>?
    @FocusState private var isCanvasFocused: Bool
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
                    .onTapGesture {
                        selectedOverlayId = nil
                        clearGuides()
                    }

                guideLayer(in: geometry.size)

                ForEach(activeOverlays) { overlay in
                    overlayHandle(overlay, in: geometry.size)
                }
            }
            .coordinateSpace(name: "overlayCanvas")
            .focusable()
            .focused($isCanvasFocused)
            .onMoveCommand { direction in
                let coarse = NSEvent.modifierFlags.contains(.shift)
                switch direction {
                case .left:
                    nudgeSelected(dx: -1, dy: 0, coarse: coarse, in: geometry.size)
                case .right:
                    nudgeSelected(dx: 1, dy: 0, coarse: coarse, in: geometry.size)
                case .up:
                    nudgeSelected(dx: 0, dy: -1, coarse: coarse, in: geometry.size)
                case .down:
                    nudgeSelected(dx: 0, dy: 1, coarse: coarse, in: geometry.size)
                @unknown default:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func guideLayer(in canvasSize: CGSize) -> some View {
        if selectedOverlayId != nil {
            let safeArea = OverlayCanvasGeometry.safeAreaRect(in: canvasSize)
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: safeArea.width, height: safeArea.height)
                .position(x: safeArea.midX, y: safeArea.midY)
                .allowsHitTesting(false)
        }

        Path { path in
            if let verticalGuide {
                let x = verticalGuide * canvasSize.width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
            }
            if let horizontalGuide {
                let y = horizontalGuide * canvasSize.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .shadow(color: .black.opacity(0.35), radius: 1)
        .allowsHitTesting(false)
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
            isCanvasFocused = true
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
                let snap = snappedCenter(
                    x: base.x + Double(translation.x),
                    y: base.y + Double(translation.y),
                    overlay: overlay,
                    scale: base.scale,
                    rotation: base.rotation,
                    in: canvasSize
                )
                verticalGuide = snap.verticalGuide
                horizontalGuide = snap.horizontalGuide
                updateDraft(
                    Project.Overlay.Transform(
                        x: Double(snap.center.x),
                        y: Double(snap.center.y),
                        scale: base.scale,
                        rotation: base.rotation
                    ),
                    overlayId: overlay.id
                )
                NSCursor.closedHand.set()
            }
            .onEnded { _ in
                finishInteraction(for: overlay)
                clearGuides()
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
                let scale = min(8, max(0.1, base.scale * ratio))
                let constrained = snappedCenter(
                    x: base.x,
                    y: base.y,
                    overlay: overlay,
                    scale: scale,
                    rotation: base.rotation,
                    in: canvasSize,
                    thresholdPixels: 0
                )
                updateDraft(
                    Project.Overlay.Transform(
                        x: Double(constrained.center.x),
                        y: Double(constrained.center.y),
                        scale: scale,
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
            keyboardCommitTask?.cancel()
            let base = draftTransform ?? overlay.transform
            interactionStartTransform = base
            draftTransform = base
            selectedOverlayId = overlay.id
            isCanvasFocused = true
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
        interactionStartTransform = nil
        lastDraftPush = .distantPast
        Task {
            await commit(final, for: overlay)
            if interactionStartTransform == nil, draftTransform == final {
                draftTransform = nil
            }
        }
    }

    private func resetInteraction() {
        interactionStartTransform = nil
        draftTransform = nil
        lastDraftPush = .distantPast
    }

    private func nudgeSelected(
        dx: CGFloat,
        dy: CGFloat,
        coarse: Bool,
        in canvasSize: CGSize
    ) {
        guard let selectedOverlayId,
              let overlay = activeOverlays.first(where: { $0.id == selectedOverlayId }) else {
            return
        }

        let base = draftTransform ?? overlay.transform
        let pixels: CGFloat = coarse ? 10 : 1
        let translation = OverlayCanvasGeometry.normalizedTranslation(
            CGSize(width: dx * pixels, height: dy * pixels),
            in: canvasSize
        )
        let snap = snappedCenter(
            x: base.x + Double(translation.x),
            y: base.y + Double(translation.y),
            overlay: overlay,
            scale: base.scale,
            rotation: base.rotation,
            in: canvasSize
        )
        let next = Project.Overlay.Transform(
            x: Double(snap.center.x),
            y: Double(snap.center.y),
            scale: base.scale,
            rotation: base.rotation
        )
        verticalGuide = snap.verticalGuide
        horizontalGuide = snap.horizontalGuide
        updateDraft(next, overlayId: overlay.id)
        scheduleKeyboardCommit(next, for: overlay)
    }

    private func scheduleKeyboardCommit(
        _ transform: Project.Overlay.Transform,
        for overlay: Project.Overlay
    ) {
        keyboardCommitTask?.cancel()
        keyboardCommitTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await commit(transform, for: overlay)
            if draftTransform == transform {
                draftTransform = nil
                clearGuides()
            }
        }
    }

    private func commit(_ transform: Project.Overlay.Transform, for overlay: Project.Overlay) async {
        playerViewModel.previewOverlayDraft(transform, overlayId: overlay.id)
        let result = await editor.updateOverlay(
            projectId: editor.project.projectId,
            overlayId: overlay.id,
            transform: transform
        )
        if case .failure(let error) = result {
            LogError(.editor, "Direct overlay edit failed: \(error.localizedDescription)")
            playerViewModel.refreshPreview(with: editor.project)
        }
    }

    private func snappedCenter(
        x: Double,
        y: Double,
        overlay: Project.Overlay,
        scale: Double,
        rotation: Double,
        in canvasSize: CGSize,
        thresholdPixels: CGFloat = 8
    ) -> OverlayCanvasGeometry.SnapResult {
        OverlayCanvasGeometry.snappedCenter(
            proposed: CGPoint(x: x, y: y),
            relativeSize: OverlayBaseSize.relativeSize(for: overlay.type),
            scale: scale,
            rotationDegrees: rotation,
            in: canvasSize,
            thresholdPixels: thresholdPixels
        )
    }

    private func clearGuides() {
        verticalGuide = nil
        horizontalGuide = nil
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

    private func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}
