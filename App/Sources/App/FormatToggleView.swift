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

    private var previewWidth: CGFloat {
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

    private var previewHeight: CGFloat {
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

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var editor = {
            let project = Project(
                schemaVersion: 1,
                projectId: "test",
                name: "Test Project",
                tags: [],
                createdAt: Date(),
                updatedAt: Date(),
                sources: Project.Sources(
                    syncReference: "screen",
                    screen: Project.Sources.MediaTrack(
                        path: "screen.mov",
                        fps: 60,
                        size: Project.Sources.Size(w: 1920, h: 1080),
                        syncOffsetMs: 0,
                        sha256: "abc",
                        sizeBytes: 1000
                    )
                ),
                timeline: Project.Timeline(duration: 10, segments: []),
                canvas: Project.Canvas(
                    format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                    background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                    layout: Project.Canvas.Layout(type: "fullscreen")
                ),
                overlays: [],
                captions: nil
            )
            return ProjectEditor(project: project)
        }()

        var body: some View {
            FormatToggleView(editor: editor)
                .padding()
        }
    }

    return PreviewWrapper()
}
