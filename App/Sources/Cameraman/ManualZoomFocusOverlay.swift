//
//  ManualZoomFocusOverlay.swift
//  App
//
//  Visual overlay showing the current manual zoom focus point and level
//  on the preview surface.
//

import SwiftUI
import EngineKit

struct ManualZoomFocusOverlay: View {
    let keyframes: [ZoomPlanGenerator.ZoomKeyframe]
    let currentTime: TimeInterval
    let size: CGSize

    private var activeKeyframe: ZoomPlanGenerator.ZoomKeyframe? {
        keyframes.last { $0.timestamp <= currentTime }
    }

    private var nextKeyframe: ZoomPlanGenerator.ZoomKeyframe? {
        keyframes.first { $0.timestamp > currentTime }
    }

    var body: some View {
        if let active = activeKeyframe, active.zoomLevel > 1.01 {
            let focusPx = CGPoint(
                x: active.focusX * size.width,
                y: active.focusY * size.height
            )
            let radius = min(size.width, size.height) / (2.0 * active.zoomLevel)

            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(focusPx)

                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .position(focusPx)
            }
            .allowsHitTesting(false)
        }
    }
}
