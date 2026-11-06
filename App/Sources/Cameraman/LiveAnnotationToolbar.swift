//
//  LiveAnnotationToolbar.swift
//  App
//
//  Floating palette for the live annotation tools. Not part of the recording.
//

import SwiftUI

struct LiveAnnotationToolbar: View {
    @ObservedObject var controller: LiveAnnotationController

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LiveAnnotationController.Tool.allCases) { tool in
                Button { controller.tool = tool } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(controller.tool == tool ? Color.accentColor.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(controller.tool == tool ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(tool.title)
                .accessibilityLabel(tool.title)
            }
            divider
            ForEach(LiveAnnotationController.palette, id: \.self) { hex in
                Button { controller.colorHex = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.primary.opacity(controller.colorHex == hex ? 0.9 : 0.25), lineWidth: controller.colorHex == hex ? 2 : 1))
                }
                .buttonStyle(.plain)
                .help("Color (1–\(LiveAnnotationController.palette.count))")
                .accessibilityLabel("Color \(hex)")
            }
            divider
            Button { controller.cycleWidth() } label: {
                Capsule().fill(.primary).frame(width: 18, height: CGFloat(controller.lineWidth) * 0.8 + 1)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Line width (W)")
            divider
            iconButton("arrow.uturn.backward", help: "Undo (⌘Z)") { controller.undo() }
            iconButton("trash", help: "Clear all") { controller.clear() }
            divider
            // Fixed width: the panel is sized once, from the first layout.
            Text(controller.tool == .pointer ? "⌘⇧D: draw" : "Esc: mouse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
        .padding(4)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemName).frame(width: 28, height: 28) }
            .buttonStyle(.plain)
            .disabled(!controller.canUndo)
            .help(help)
            .accessibilityLabel(help)
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 4)
    }
}
