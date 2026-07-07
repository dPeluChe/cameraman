//
//  ManualZoomFocusOverlay.swift
//  App
//
//  Visual overlay showing the current manual zoom focus point and level
//  on the preview surface. When interactive, accepts clicks to set the
//  focus point of the selected keyframe (or create a new one at playhead).
//

import SwiftUI
import EngineKit

struct ManualZoomFocusOverlay: View {
    let keyframes: [ZoomPlanGenerator.ZoomKeyframe]
    let currentTime: TimeInterval
    let size: CGSize
    var isInteractive: Bool = false
    var selectedKeyframeId: UUID? = nil
    var onTap: ((CGPoint) -> Void)? = nil

    private var activeKeyframe: ZoomPlanGenerator.ZoomKeyframe? {
        keyframes.last { $0.timestamp <= currentTime }
    }

    var body: some View {
        ZStack {
            if let active = activeKeyframe, active.zoomLevel > 1.01 {
                let focusPx = CGPoint(
                    x: active.focusX * size.width,
                    y: active.focusY * size.height
                )
                let radius = min(size.width, size.height) / (2.0 * active.zoomLevel)

                Circle()
                    .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(focusPx)

                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .position(focusPx)
            }

            // Highlight selected keyframe's focus point
            if let selId = selectedKeyframeId,
               let sel = keyframes.first(where: { $0.id == selId }) {
                let px = CGPoint(x: sel.focusX * size.width, y: sel.focusY * size.height)
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .position(px)
            }

            // Interactive crosshair when in set-focus mode
            if isInteractive {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let normX = max(0, min(1, Double(value.location.x / size.width)))
                                let normY = max(0, min(1, Double(value.location.y / size.height)))
                                onTap?(CGPoint(x: normX, y: normY))
                            }
                    )
            }
        }
        .allowsHitTesting(isInteractive)
    }
}
