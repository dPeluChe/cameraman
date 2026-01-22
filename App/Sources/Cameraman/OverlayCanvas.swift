//
//  OverlayCanvas.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    var overlayCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                // Background
                canvasBackground

                // Existing overlays
                ForEach(editor.project.overlays) { overlay in
                    renderOverlay(overlay, in: proxy.size)
                        .overlay(
                            selectionBorder(for: overlay)
                                .opacity(selectedOverlayId == overlay.id ? 1.0 : 0.0)
                        )
                        .gesture(dragGesture(for: overlay, in: proxy.size))
                        .gesture(resizeGesture(for: overlay, in: proxy.size))
                }

                // Creating overlay preview
                if isCreatingOverlay {
                    creationPreview
                }
            }
            .gesture(createOverlayGesture(in: proxy.size))
            .onTapGesture { location in
                // Deselect if tapping empty space
                if overlayAtPoint(location, in: proxy.size) == nil {
                    selectedOverlayId = nil
                }
            }
        }
        .frame(height: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    var canvasBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}
