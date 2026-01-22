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
        // Main window with recording controls
        WindowGroup {
            AppNavigation()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
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

        // Recording Controls Window (Standalone)
        WindowGroup(id: "recording-controls") {
            RecordingControlView()
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                .onAppear {
                    // Ensure window is properly sized and positioned
                    NSApp.windows.first { $0.title == "recording-controls" }?.center()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(arrayLiteral: "recording-controls")) // Only open on explicit request
    }
}
