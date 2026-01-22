//
//  OverlayCreation.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    // MARK: - Overlay Creation

    var creationPreview: some View {
        let rect = CGRect(
            x: min(creationStartPoint.x, creationCurrentPoint.x),
            y: min(creationStartPoint.y, creationCurrentPoint.y),
            width: abs(creationCurrentPoint.x - creationStartPoint.x),
            height: abs(creationCurrentPoint.y - creationStartPoint.y)
        )

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    func createOverlay(from start: CGPoint, to end: CGPoint) {
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        guard width > 0.01 || height > 0.01 else { return }

        let centerX = min(start.x, end.x) + width / 2.0
        let centerY = min(start.y, end.y) + height / 2.0

        let overlay = Project.Overlay(
            id: UUID(),
            type: selectedTool.overlayType,
            start: playheadTime,
            end: playheadTime + 5.0, // Default 5 seconds
            transform: Project.Overlay.Transform(
                x: centerX,
                y: centerY,
                scale: 1.0,
                rotation: 0.0
            ),
            style: defaultStyle(for: selectedTool),
            animation: nil
        )

        Task {
            _ = await editor.addOverlay(projectId: editor.project.projectId, overlay: overlay)
            selectedOverlayId = overlay.id
        }
    }
}
