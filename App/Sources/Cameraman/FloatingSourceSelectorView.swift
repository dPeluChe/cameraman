//
//  FloatingSourceSelectorView.swift
//  Cameraman
//
//  Created by Droid on 2026-01-21.
//  Professional floating source selector with live preview
//

import SwiftUI
import ScreenCaptureKit
import EngineKit

/// Professional floating window for selecting recording source
struct FloatingSourceSelectorView: View {
    @StateObject private var viewModel = SourceSelectorViewModel()
    @Environment(\.dismiss) private var dismiss
    let onSourceSelected: (RecordingSourceSelectorView.CaptureSource) -> Void
    
    init(onSourceSelected: @escaping (RecordingSourceSelectorView.CaptureSource) -> Void) {
        self.onSourceSelected = onSourceSelected
        print("[WINDOW] 🟡 FloatingSourceSelectorView init")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(Color.white.opacity(0.15))

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Source type selector
                    sourceTypePicker

                    // Source list
                    sourceList

                    // Preview section
                    if viewModel.previewImage != nil {
                        previewSection
                    }
                }
                .padding()
            }

            // Footer
            footer
        }
        .frame(width: 560, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        .onAppear {
            Task {
                await viewModel.loadSources(for: .display)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Recording Source")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Choose what you want to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var sourceTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(FloatingSourceType.allCases, id: \.self) { type in
                FloatingSourceTypeButton(
                    type: type,
                    isSelected: viewModel.selectedTab == type.rawValue
                ) {
                    Task {
                        await viewModel.loadSources(for: type.rawValue)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var sourceList: some View {
        if viewModel.permissionDenied {
            permissionView
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            sourcesContent
        }
    }

    @ViewBuilder
    private var sourcesContent: some View {
        switch viewModel.selectedTab {
        case .display:
            displaySourcesList
        case .window:
            windowSourcesList
        case .application:
            applicationSourcesList
        }
    }

    private var displaySourcesList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.displaySources) { source in
                ProfessionalDisplaySourceRow(
                    source: source,
                    onTap: {
                        selectSource(.display(source))
                    },
                    onPreview: {
                        Task {
                            await viewModel.capturePreview(display: source)
                        }
                    }
                )
            }
        }
    }

    private var windowSourcesList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.windowSources) { source in
                ProfessionalWindowSourceRow(
                    source: source,
                    onTap: {
                        selectSource(.window(source))
                    },
                    onPreview: {
                        Task {
                            await viewModel.capturePreview(window: source)
                        }
                    }
                )
            }
        }
    }

    private var applicationSourcesList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.applicationSources) { source in
                ProfessionalApplicationSourceRow(
                    source: source,
                    onTap: {
                        selectSource(.application(source))
                    }
                )
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            if let image = viewModel.previewImage {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .frame(height: 180)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Permission Required")
                .font(.headline)

            Text("Cameraman needs screen recording permission to capture your screen.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    Task {
                        await viewModel.openSystemSettings()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Check Again") {
                    Task {
                        await viewModel.loadSources(for: viewModel.selectedTab)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("⌘+Click for quick preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Continue") {
                // Continue with selected source
            }
            .buttonStyle(.borderedProminent)
            .disabled(true) // Enable when source is selected
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func selectSource(_ source: RecordingSourceSelectorView.CaptureSource) {
        onSourceSelected(source)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    FloatingSourceSelectorView { source in
        print("Selected: \(source)")
    }
}
