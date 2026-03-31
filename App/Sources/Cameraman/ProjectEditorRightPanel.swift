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
                            PiPConfigurationView(editor: editor)
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
                    
                    // Overlays Group
                    ConfigGroup(title: "Overlays", isExpanded: $isOverlaysExpanded) {
                        // Using a playhead constant here since we are just configuring overlay logic, 
                        // but ideally OverlayEditorView needs the binding if it scrubs.
                        // For the inspector, we mostly want the list/add buttons.
                        // We can pass .constant(0) if it's just for property editing, 
                        // or rewire if needed.
                        OverlayEditorView(editor: editor, playheadTime: .constant(0))
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
    }
}
