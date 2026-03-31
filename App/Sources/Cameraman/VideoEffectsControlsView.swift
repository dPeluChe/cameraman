//
//  VideoEffectsControlsView.swift
//  App
//
//  Controls for video corner radius, shadow, and padding.
//

import SwiftUI
import EngineKit

struct VideoEffectsControlsView: View {
    @ObservedObject var editor: ProjectEditor

    private var canvas: Project.Canvas { editor.project.canvas }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Corner Radius
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Corner Radius")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(canvas.videoCornerRadius))px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { canvas.videoCornerRadius },
                    set: { updateCanvas { $0.videoCornerRadius = $1 }($0) }
                ), in: 0...16, step: 1)
                .controlSize(.small)
            }

            // Shadow
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Shadow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(canvas.videoShadowIntensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { canvas.videoShadowIntensity },
                    set: { updateCanvas { $0.videoShadowIntensity = $1 }($0) }
                ), in: 0...1, step: 0.05)
                .controlSize(.small)
            }

            // Padding
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Padding")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(canvas.padding * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { canvas.padding },
                    set: { updateCanvas { $0.padding = $1 }($0) }
                ), in: 0...0.3, step: 0.01)
                .controlSize(.small)
            }
        }
    }

    private func updateCanvas(_ modify: @escaping (inout Project.Canvas, Double) -> Void) -> (Double) -> Void {
        { newValue in
            var updatedProject = editor.project
            modify(&updatedProject.canvas, newValue)
            Task {
                await editor.setProject(updatedProject)
            }
        }
    }
}
