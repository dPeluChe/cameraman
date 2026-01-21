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
            ForEach(SourceType.allCases, id: \.self) { type in
                SourceTypeButton(
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

// MARK: - Source Type Button

private struct SourceTypeButton: View {
    let type: SourceType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                Text(type.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private enum SourceType: CaseIterable {
    case display
    case window
    case application

    var label: String {
        switch self {
        case .display: return "Displays"
        case .window: return "Windows"
        case .application: return "Apps"
        }
    }

    var icon: String {
        switch self {
        case .display: return "display"
        case .window: return "rectangle.on.rectangle"
        case .application: return "app.fill"
        }
    }

    var rawValue: SourceSelectorViewModel.SourceTab {
        switch self {
        case .display: return .display
        case .window: return .window
        case .application: return .application
        }
    }
}

// MARK: - Professional Source Rows

private struct ProfessionalDisplaySourceRow: View {
    let source: SourceSelector.DisplaySource
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Display icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 40)

                    Image(systemName: "display")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }

                // Display info
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        badge("\(source.width)×\(source.height)")
                        badge("\(Int(source.refreshRate)) Hz")

                        if source.isMain {
                            badge("Main", color: .green)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Preview (⌘+Click)")
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((color ?? .secondary).opacity(0.15))
            .cornerRadius(4)
    }
}

private struct ProfessionalWindowSourceRow: View {
    let source: SourceSelector.WindowSource
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Window icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 48, height: 38)

                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 16))
                        .foregroundStyle(.purple)
                }

                // Window info
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(source.applicationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text("\(source.width)×\(source.height)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !source.isOnScreen {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("Off-screen")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfessionalApplicationSourceRow: View {
    let source: SourceSelector.ApplicationSource
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // App icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }

                // App info
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(source.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FloatingSourceSelectorView { source in
        print("Selected: \(source)")
    }
}
