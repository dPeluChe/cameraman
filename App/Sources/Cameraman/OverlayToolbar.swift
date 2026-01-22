//
//  OverlayToolbar.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

extension OverlayEditorView {
    var toolbar: some View {
        HStack(spacing: 8) {
            Text("Overlays")
                .font(.headline)

            Spacer()

            HStack(spacing: 4) {
                ForEach(availableTools, id: \.self) { tool in
                    toolButton(for: tool)
                }
            }

            Spacer()

            Button(action: deleteSelectedOverlay) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedOverlayId == nil)
        }
    }

    func toolButton(for tool: OverlayTool) -> some View {
        Button(action: { selectTool(tool) }) {
            Label(tool.label, systemImage: tool.icon)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(tool.shortcut, modifiers: tool.modifiers)
        .background(selectedTool == tool ? Color.accentColor.opacity(0.3) : Color.clear)
    }
}
