//
//  ProjectEditorLeftPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

struct LeftPanel: View {
    @ObservedObject var editor: ProjectEditor
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Assets")
                    .font(.headline)
                Spacer()
                Button {
                    startNewTake()
                } label: {
                    Label("Rec Take", systemImage: "record.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Record new take")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            List {
                Section("Sources") {
                    AssetRow(icon: "display", title: "Screen Recording", subtitle: "Main")
                    if editor.project.primarySources?.camera != nil {
                        AssetRow(icon: "video.fill", title: "Camera Feed", subtitle: "1080p")
                    }
                    if editor.project.primarySources?.audio != nil {
                        AssetRow(icon: "mic.fill", title: "Microphone", subtitle: "Audio Track")
                        AssetRow(icon: "speaker.wave.2.fill", title: "System Audio", subtitle: "Audio Track")
                    }
                }
                
                Section("Takes") {
                    ForEach(editor.project.takes) { take in
                        AssetRow(icon: "video.badge.plus", title: take.name, subtitle: formattedDate(take.createdAt))
                            .onDrag {
                                // Provide take ID and duration for drag & drop
                                let provider = NSItemProvider(object: take.id.uuidString as NSString)
                                // We can also provide duration if we calculate it from sources, 
                                // but for now ID is enough to look it up in the drop target
                                return provider
                            }
                    }
                }
                
                Section("Layers") {
                     ForEach(editor.project.timeline.segments) { segment in
                         AssetRow(icon: "film", title: "Segment \(segment.id.prefix(4))", subtitle: "\(String(format: "%.1f", segment.sourceOut - segment.sourceIn))s")
                     }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func startNewTake() {
        // Configure recording view model for this project
        if let recViewModel = RecordingStateManager.shared.viewModel {
            recViewModel.targetProjectId = editor.project.projectId
        }
        
        // Open recording window
        NotificationCenter.default.post(name: .openRecordingWindow, object: nil)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AssetRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
