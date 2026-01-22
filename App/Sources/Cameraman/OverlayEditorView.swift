//
//  OverlayEditorView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//  Épica UI-G — Overlay Editor (P0)
//

import SwiftUI
import EngineKit
import CoreGraphics

// MARK: - Main Overlay Editor View

struct OverlayEditorView: View {
    @ObservedObject var editor: ProjectEditor
    @Binding var playheadTime: TimeInterval

    @State var selectedTool: OverlayTool = .arrow
    @State var selectedOverlayId: UUID?
    @State var isCreatingOverlay = false
    @State var creationStartPoint: CGPoint = .zero
    @State var creationCurrentPoint: CGPoint = .zero

    let availableTools: [OverlayTool] = [.arrow, .rect, .line, .text]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toolbar
            toolbar

            Divider()

            // Canvas with overlays
            overlayCanvas

            // Style inspector (when overlay is selected)
            if let overlayId = selectedOverlayId,
               let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) {
                Divider()
                styleInspector(for: overlay)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
