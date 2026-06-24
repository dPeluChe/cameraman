//
//  TelemetryControlsView.swift
//  App
//
//  Created by Ralphy on 2026-01-20.
//

import SwiftUI
import EngineKit

/// Controls for toggling telemetry visualization in the preview
struct TelemetryControlsView: View {
    @ObservedObject var viewModel: PreviewPlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Telemetry Visualization")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            HStack(spacing: 16) {
                // Cursor toggle
                Toggle("Show Cursor", isOn: $viewModel.showCursor)
                    .toggleStyle(.checkbox)
                    .help("Show cursor position and movement")

                // Clicks toggle
                Toggle("Show Clicks", isOn: $viewModel.showClicks)
                    .toggleStyle(.checkbox)
                    .help("Visualize mouse click events")

                // Keystrokes toggle
                Toggle("Show Keystrokes", isOn: $viewModel.showKeystrokes)
                    .toggleStyle(.checkbox)
                    .help("Display keyboard inputs")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Telemetry info
            if hasTelemetryData {
                telemetryInfoView
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                Text("No telemetry data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.medium)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var telemetryInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sources = viewModel.project?.sources, sources.telemetry?.cursor != nil {
                HStack {
                    Image(systemName: "cursorarrow")
                        .foregroundStyle(.blue)
                    Text("Cursor tracking available")
                }
            }

            if let sources = viewModel.project?.sources, sources.telemetry?.keys != nil {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.green)
                    Text("Keystroke recording available")
                }
            }
        }
    }

    private var hasTelemetryData: Bool {
        let project = viewModel.project
        if let sources = project?.sources {
            return sources.telemetry?.cursor != nil || sources.telemetry?.keys != nil
        }
        return false
    }
}

// MARK: - Preview

#Preview {
    TelemetryControlsView(viewModel: PreviewPlayerViewModel())
}
