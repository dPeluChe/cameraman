//
//  OverlayGestures.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    // MARK: - Gestures

    func createOverlayGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isCreatingOverlay {
                    isCreatingOverlay = true
                    creationStartPoint = value.startLocation
                    creationCurrentPoint = value.location
                } else {
                    creationCurrentPoint = value.location
                }
            }
            .onEnded { value in
                let startPoint = normalizedPoint(creationStartPoint, in: size)
                let endPoint = normalizedPoint(value.location, in: size)

                createOverlay(from: startPoint, to: endPoint)

                isCreatingOverlay = false
                creationStartPoint = .zero
                creationCurrentPoint = .zero
            }
    }

    func dragGesture(for overlay: Project.Overlay, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedOverlayId == overlay.id else { return }

                let deltaX = Double(value.translation.width / size.width)
                let deltaY = Double(value.translation.height / size.height)

                Task {
                    _ = await editor.updateOverlay(
                        projectId: editor.project.projectId,
                        overlayId: overlay.id,
                        transform: Project.Overlay.Transform(
                            x: overlay.transform.x + deltaX,
                            y: overlay.transform.y + deltaY,
                            scale: overlay.transform.scale,
                            rotation: overlay.transform.rotation
                        )
                    )
                }
            }
    }

    func resizeGesture(for overlay: Project.Overlay, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedOverlayId == overlay.id else { return }

                // Calculate scale based on drag distance
                let scaleDelta = Double(value.translation.width / 100.0)
                let newScale = max(0.1, overlay.transform.scale + scaleDelta)

                Task {
                    _ = await editor.updateOverlay(
                        projectId: editor.project.projectId,
                        overlayId: overlay.id,
                        transform: Project.Overlay.Transform(
                            x: overlay.transform.x,
                            y: overlay.transform.y,
                            scale: newScale,
                            rotation: overlay.transform.rotation
                        )
                    )
                }
            }
    }
}
