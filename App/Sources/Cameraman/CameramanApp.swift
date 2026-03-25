//
//  App.swift
//  App
//
//  Created by Ralphy on 2026-01-19.
//

import Combine
import SwiftUI
import EngineKit

/// Main app entry point
@main
struct CameramanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window with project library and editor
        WindowGroup(id: "main-editor") {
            AppNavigation()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // Add Preferences menu item
            CommandGroup(replacing: .appSettings) {
                Button {
                    // Open preferences window
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Text("Preferences...")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // Add Recording menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    // Open recording controls window
                    NSApp.sendAction(Selector(("showRecordingControlsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Recording Controls Window (Standalone, single instance)
        Window("Recording", id: "recording-controls") {
            RecordingControlView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 480)
    }
}
