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
                .accessibilityLabel("Color \(hex)")
            }
            divider
            Button { cycleWidth() } label: {
                Capsule().fill(.primary).frame(width: 18, height: CGFloat(controller.lineWidth) * 0.8 + 1)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Line width")
            divider
            Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .disabled(!controller.canUndo)
                .help("Undo (⌘Z)")
            Button { controller.clear() } label: { Image(systemName: "trash").frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .disabled(!controller.canUndo)
                .help("Clear all")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
        .padding(4)
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 4)
    }

    private func cycleWidth() {
        let widths = LiveAnnotationController.widths
        let next = (widths.firstIndex(of: controller.lineWidth) ?? 0) + 1
        controller.lineWidth = widths[next % widths.count]
    }
}
