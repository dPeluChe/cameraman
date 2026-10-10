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
    /// Moves the playhead so a newly added overlay is visible while paused.
    var onSeek: ((TimeInterval) -> Void)?

    @State var selectedTool: OverlayTool = .arrow
    /// The style inspector is tall; collapse it to make room for adding another element.
    @State private var inspectorExpanded = true

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
                            if selectedOverlayId == overlay.id {
                                Image(systemName: inspectorExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .help(inspectorExpanded ? "Collapse the style inspector" : "Expand the style inspector")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedOverlayId == overlay.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            inspectorExpanded = selectedOverlayId == overlay.id ? !inspectorExpanded : true
                            selectedOverlayId = overlay.id
                        }
                    }
                }
            }

            // Style inspector (when overlay is selected)
            if inspectorExpanded,
               let overlayId = selectedOverlayId,
               let overlay = editor.project.overlays.first(where: { $0.id == overlayId }) {
                Divider()
                styleInspector(for: overlay)
            }
        }
    }

}
