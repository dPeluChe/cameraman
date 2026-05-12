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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overlays")
                    .font(.headline)

                Spacer()

                Button(action: deleteSelectedOverlay) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(selectedOverlayId == nil)
                .help("Delete selected overlay")
            }

            HStack(spacing: 4) {
                ForEach(availableTools, id: \.self) { tool in
                    toolButton(for: tool)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
