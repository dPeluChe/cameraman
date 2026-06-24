//
//  ProjectEditorRightPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

struct RightPanel: View {
    @ObservedObject var editor: ProjectEditor
    var selectedSegmentId: String?
    var selectedMediaItemId: UUID?
    var playerViewModel: PreviewPlayerViewModel? = nil

    // Binding states for expansion
    @Binding var isLayoutExpanded: Bool
    @Binding var isFormatExpanded: Bool
    @Binding var isCameraExpanded: Bool
    @Binding var isVideoEffectsExpanded: Bool
    @Binding var isBackgroundExpanded: Bool
    @Binding var isZoomExpanded: Bool
    @Binding var isOverlaysExpanded: Bool
    @Binding var isExportExpanded: Bool
    @Binding var showExportModal: Bool
    @Binding var showTranscriptionModal: Bool
    @Binding var showAISuggestionsModal: Bool

    // Subtitles section manages its own expansion locally so the parent layout
    // doesn't need a new binding wired through every call site.
    @State private var isSubtitlesExpanded: Bool = false
    @State private var isCaptionsExpanded: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                Text("Configuration")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                
                Divider()
                
                VStack(spacing: 0) {
                    // Layout Group
                    ConfigGroup(title: "Layout", isExpanded: $isLayoutExpanded) {
                        LayoutSelectorView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Format Group
                    ConfigGroup(title: "Format", isExpanded: $isFormatExpanded) {
                        FormatToggleView(editor: editor)
                    }
                    
                    if editor.project.canvas.layout.camera != nil {
                        Divider()
                        
                        // Camera Group
                        ConfigGroup(title: "Camera", isExpanded: $isCameraExpanded) {
                            PiPConfigurationView(
                                editor: editor,
                                selectedSegmentId: selectedSegmentId,
                                playerViewModel: playerViewModel
                            )
                        }
                    }
                    
                    Divider()

                    // Video Effects Group
                    ConfigGroup(title: "Video Effects", isExpanded: $isVideoEffectsExpanded) {
                        VideoEffectsControlsView(editor: editor)
                    }

                    Divider()

                    // Background Group
                    ConfigGroup(title: "Background", isExpanded: $isBackgroundExpanded) {
                        BackgroundControlsView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Auto-Zoom Group
                    ConfigGroup(title: "Auto-Zoom", isExpanded: $isZoomExpanded) {
                         ZoomControlsView(editor: editor)
                    }
                    
                    Divider()
                    
                    // Media Items (Image Overlays)
                    if !editor.project.mediaItems.isEmpty {
                        ConfigGroup(title: "Media Items", isExpanded: .constant(true)) {
                            MediaItemInspectorView(
                                editor: editor,
                                selectedMediaItemId: selectedMediaItemId
                            )
                        }
                        
                        Divider()
                    }
                    
                    // Overlays Group
                    ConfigGroup(title: "Overlays", isExpanded: $isOverlaysExpanded) {
                        OverlayEditorView(
                            editor: editor,
                            playheadTime: Binding(
                                get: { playerViewModel?.currentTime ?? 0 },
                                set: { _ in }
                            )
                        )
                    }
                    
                    Divider()

                    // Subtitles Group
                    ConfigGroup(title: "Subtitles", isExpanded: $isSubtitlesExpanded) {
                        SubtitleEditorView(
                            editor: editor,
                            onSeek: { time in playerViewModel?.seek(to: time) }
                        )
                    }

                    Divider()

                    // Captions & AI tools
                    ConfigGroup(title: "Captions & AI", isExpanded: $isCaptionsExpanded) {
                        VStack(spacing: 8) {
                            Button {
                                showTranscriptionModal = true
                            } label: {
                                HStack {
                                    Image(systemName: "captions.bubble")
                                    Text("Generate Captions...")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showAISuggestionsModal = true
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("AI Assistant (MCP)...")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .help("Connect an AI assistant via MCP to edit this project")
                        }
                        .padding(.top, 8)
                    }

                    Divider()

                    // Export Section (Always visible or in a group)
                    ConfigGroup(title: "Export", isExpanded: $isExportExpanded) {
                        Button {
                            showExportModal = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Video...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(width: 300)
    }
}

struct ConfigGroup<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .padding(.top, 8)
                .padding(.bottom, 12)
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Disable disclosure expand/collapse animation: it caused the whole
        // right panel to jitter horizontally when adaptive grids reflowed.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
