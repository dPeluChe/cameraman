//
//  RecordingControlView+SourcePicker.swift
//  App
//
//  Extracted from RecordingControlView.swift
//  Source picker step for recording flow
//

import SwiftUI
import EngineKit

struct SourcePickerView: View {
    @ObservedObject var sourceViewModel: SourceSelectorViewModel
    let onSelectSource: (RecordingSourceSelectorView.CaptureSource) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            header
            
            tabButtons
            
            if sourceViewModel.permissionDenied {
                permissionView
            } else {
                sourceList
            }
            
            previewView
        }
    }
    
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
    
    @ViewBuilder
    private var sourceList: some View {
        VStack(spacing: 6) {
            switch sourceViewModel.selectedTab {
            case .display:
                ForEach(sourceViewModel.displaySources, id: \.id) { source in
                    ProfessionalDisplaySourceRow(source: source, onTap: {
                        onSelectSource(.display(source))
                    }, onPreview: {
                        Task { await sourceViewModel.capturePreview(display: source) }
                    })
                }
            case .window:
                ForEach(sourceViewModel.windowSources, id: \.id) { source in
                    ProfessionalWindowSourceRow(source: source, onTap: {
                        onSelectSource(.window(source))
                    }, onPreview: {
                        Task { await sourceViewModel.capturePreview(window: source) }
                    })
                }
            case .application:
                ForEach(sourceViewModel.applicationSources, id: \.id) { source in
                    ProfessionalApplicationSourceRow(source: source, onTap: {
                        onSelectSource(.application(source))
                    })
                }
            }
        }
        
        if sourceViewModel.displaySources.isEmpty && !sourceViewModel.permissionDenied {
            ProgressView()
                .frame(height: 60)
        }
    }
    
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
    
    @ViewBuilder
    private var previewView: some View {
        if let image = sourceViewModel.previewImage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
