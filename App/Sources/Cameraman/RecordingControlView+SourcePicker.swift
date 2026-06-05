//
//  RecordingControlView+SourcePicker.swift
//  App
//
//  Extracted from RecordingControlView.swift
//  Source picker step for recording flow: fixed preview on top + compact chips.
//

import SwiftUI
import EngineKit

struct SourcePickerView: View {
    @ObservedObject var sourceViewModel: SourceSelectorViewModel
    let onSelectSource: (RecordingSourceSelectorView.CaptureSource) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        VStack(spacing: 14) {
            header
            tabButtons

            if sourceViewModel.permissionDenied {
                permissionView
            } else {
                previewPanel
                chipsGrid
                continueButton
            }
        }
    }

    // MARK: - Header & Tabs

    private var header: some View {
        HStack {
            Text("Step 1")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            Text("Select what to record")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 6) {
            ForEach(FloatingSourceType.allCases, id: \.self) { type in
                FloatingSourceTypeButton(
                    type: type,
                    isSelected: sourceViewModel.selectedTab == type.rawValue
                ) {
                    Task { await sourceViewModel.loadSources(for: type.rawValue) }
                }
            }
        }
    }

    // MARK: - Preview (fixed, always visible)

    private var previewPanel: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.15))

                if let image = sourceViewModel.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else if sourceViewModel.displaySources.isEmpty
                    && sourceViewModel.windowSources.isEmpty
                    && sourceViewModel.applicationSources.isEmpty {
                    ProgressView()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 22))
                        Text("Tap a source to preview")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let name = activeSourceName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Chips

    private var chipsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                switch sourceViewModel.selectedTab {
                case .display:
                    ForEach(sourceViewModel.displaySources, id: \.id) { source in
                        chip(label: source.name, subtitle: "\(source.width)×\(source.height)", id: source.id) {
                            Task { await sourceViewModel.capturePreview(display: source) }
                        }
                    }
                case .window:
                    ForEach(sourceViewModel.windowSources, id: \.id) { source in
                        chip(label: source.title, subtitle: source.applicationName, id: source.id) {
                            Task { await sourceViewModel.capturePreview(window: source) }
                        }
                    }
                case .application:
                    ForEach(sourceViewModel.applicationSources, id: \.id) { source in
                        chip(label: source.name, subtitle: nil, id: source.id) {
                            Task { await sourceViewModel.capturePreview(application: source) }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxHeight: 150)
    }

    private func chip(label: String, subtitle: String?, id: String, action: @escaping () -> Void) -> some View {
        let isActive = sourceViewModel.activeSourceID == id
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isActive ? Color.accentColor.opacity(0.22) : Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            if let source = activeSource { onSelectSource(source) }
        } label: {
            Text(activeSource != nil ? "Continue" : "Select a source")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .disabled(activeSource == nil)
    }

    // MARK: - Permission

    private var permissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Screen recording permission required")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Open Settings") {
                    Task { await sourceViewModel.openSystemSettings() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Retry") {
                    Task { await sourceViewModel.loadSources(for: sourceViewModel.selectedTab) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Active source resolution

    private var activeSource: RecordingSourceSelectorView.CaptureSource? {
        guard let id = sourceViewModel.activeSourceID else { return nil }
        switch sourceViewModel.selectedTab {
        case .display:
            return sourceViewModel.displaySources.first { $0.id == id }.map { .display($0) }
        case .window:
            return sourceViewModel.windowSources.first { $0.id == id }.map { .window($0) }
        case .application:
            return sourceViewModel.applicationSources.first { $0.id == id }.map { .application($0) }
        }
    }

    private var activeSourceName: String? {
        switch activeSource {
        case .display(let s): return s.name
        case .window(let s): return "\(s.title) — \(s.applicationName)"
        case .application(let s): return s.name
        case nil: return nil
        }
    }
}
