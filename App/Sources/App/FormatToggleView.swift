//
//  FormatToggleView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

/// View for toggling between 16:9 and 9:16 aspect ratio formats with visual preview
struct FormatToggleView: View {
    @ObservedObject var editor: ProjectEditor

    private let availableFormats: [CanvasLayout.AspectRatio] = [.landscape16_9, .portrait9_16]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(availableFormats, id: \.self) { format in
                    FormatButton(
                        format: format,
                        isSelected: format == currentFormat
                    ) {
                        Task {
                            _ = await editor.setFormat(format)
                        }
                    }
                }
            }
        }
    }

    private var currentFormat: CanvasLayout.AspectRatio {
        CanvasLayout.AspectRatio(rawValue: editor.project.canvas.format.aspect) ?? .landscape16_9
    }
}

/// Format button with visual preview
private struct FormatButton: View {
    let format: CanvasLayout.AspectRatio
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Preview rectangle showing aspect ratio
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(
                            width: previewWidth,
                            height: previewHeight
                        )

                    // Aspect ratio label
                    Text(format.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(format.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(width: 100)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .help("Switch to \(format.displayName) format")
    }

    private var previewWidth: CoreGraphics.CGFloat {
        switch format {
        case .landscape16_9:
            return 60
        case .portrait9_16:
            return 34
        case .square1_1:
            return 50
        case .landscape4_3:
            return 55
        }
    }

    private var previewHeight: CoreGraphics.CGFloat {
        switch format {
        case .landscape16_9:
            return 34
        case .portrait9_16:
            return 60
        case .square1_1:
            return 50
        case .landscape4_3:
            return 41
        }
    }
}
