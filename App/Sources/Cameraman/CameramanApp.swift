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
        // Main window with project library and editor (single-instance)
        Window("Projects", id: WindowID.mainEditor) {
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

            // File → Export... (only triggers when an editor is loaded)
            CommandGroup(after: .saveItem) {
                Button("Export...") {
                    NotificationCenter.default.post(name: .openExportModal, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Project Studio Help") {
                    NSWorkspace.shared.open(AppLinks.help)
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("View on GitHub") {
                    NSWorkspace.shared.open(AppLinks.repo)
                }

                Button("Contact Support") {
                    NSWorkspace.shared.open(AppLinks.contact)
                }

                Divider()

                Button("Support with GitHub Sponsors ♥") {
                    NSWorkspace.shared.open(AppLinks.sponsors)
                }

                Button("Donate via PayPal") {
                    NSWorkspace.shared.open(AppLinks.paypal)
                }

                Divider()

                Button("Check for Updates...") {
                    AppUpdater.shared.checkForUpdates(userInitiated: true)
                }
            }
        }

        // Recording Controls Window (Standalone, single instance)
        Window("Recording", id: WindowID.recordingControls) {
            RecordingControlView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 480)
    }
}
