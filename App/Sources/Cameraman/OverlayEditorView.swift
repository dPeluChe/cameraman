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
    @Binding var selectedOverlayId: UUID?

    @State var selectedTool: OverlayTool = .arrow

    let availableTools: [OverlayTool] = [.arrow, .rect, .line, .text, .image]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toolbar (add overlay buttons)
            toolbar

            // List of existing overlays
            if editor.project.overlays.isEmpty {
                Text("No overlays yet. Use the tools above to add.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(editor.project.overlays) { overlay in
                        HStack {
                            Image(systemName: OverlayDisplayInfo.icon(for: overlay.type))
                                .font(.caption)
                                .frame(width: 16)
                            Text(overlay.type.rawValue.capitalized)
                                .font(.caption)
                            Spacer()
                            Text("\(String(format: "%.2f", overlay.start))s - \(String(format: "%.2f", overlay.end))s")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedOverlayId == overlay.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedOverlayId = overlay.id
                        }
                    }
                }
            }

            // Style inspector (when overlay is selected)
            if let overlayId = selectedOverlayId,
               let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) {
                Divider()
                styleInspector(for: overlay)
            }
        }
    }

}
