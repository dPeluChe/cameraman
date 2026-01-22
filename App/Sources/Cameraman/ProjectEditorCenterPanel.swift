//
//  ProjectEditorCenterPanel.swift
//  App
//
//  Created by Ralphy on 2026-01-22.
//

import SwiftUI
import EngineKit

struct CenterPanel: View {
    @ObservedObject var viewModel: ProjectEditorViewModel
    @Binding var showExportModal: Bool
    @Binding var showTranscriptionModal: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            ZStack {
                Color.black
                
                if let editor = viewModel.editor {
                    PreviewPlayerView(
                        project: editor.project,
                        projectDirectory: viewModel.projectDirectory
                    )
                } else if viewModel.isLoading {
                    ProgressView()
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Timeline
            if let editor = viewModel.editor {
                TimelineView(
                    editor: editor,
                    playheadTime: $viewModel.playheadTime,
                    projectDirectory: viewModel.projectDirectory
                )
                .frame(height: 300)
            } else {
                 Color(NSColor.controlBackgroundColor)
                    .frame(height: 300)
            }
        }
    }
}
