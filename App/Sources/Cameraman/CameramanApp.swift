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

    init() {
        Self.leaveSandboxContainer()
    }

    /// Once, before anything opens a project: 0.8 dropped the sandbox, so data moves out of the container.
    private static func leaveSandboxContainer() {
        let key = "migration.leftSandboxContainer"
        guard let id = Bundle.main.bundleIdentifier, !UserDefaults.standard.bool(forKey: key) else { return }
        let migration = ContainerMigration(bundleIdentifier: id)
        migration.importPreferences(into: .standard, bundleIdentifier: id)
        let moved = migration.run()
        UserDefaults.standard.set(true, forKey: key)
        LogInfo(.ui, "[Migration] moved \(moved) item(s) out of the sandbox container")
    }

    var body: some Scene {
        // Main window with project library and editor (single-instance)
        Window("Projects", id: WindowID.mainEditor) {
            AppNavigation()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // File → New Recording
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    NSApp.sendAction(Selector(("showRecordingControlsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // File → Export
            CommandGroup(after: .saveItem) {
                Button("Export...") {
                    NotificationCenter.default.post(name: .openExportModal, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Generate Subtitles...") {
                    NotificationCenter.default.post(name: .openTranscriptionModal, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("AI Assistant (MCP)...") {
                    NotificationCenter.default.post(name: .openAISuggestions, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Cameraman Help") {
                    NSWorkspace.shared.open(AppLinks.help)
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("View on GitHub") {
                    NSWorkspace.shared.open(AppLinks.repo)
                }

                Button("Check for Updates...") {
                    AppUpdater.shared.checkForUpdates(userInitiated: true)
                }

                Button("Report a Bug...") {
                    DiagnosticsWindowController.shared.show()
                }

                Button("Contact Support...") {
                    ContactSupportWindowController.shared.show()
                }

                Divider()

                Button("Support with GitHub Sponsors ♥") {
                    NSWorkspace.shared.open(AppLinks.sponsors)
                }

                Button("Donate via PayPal") {
                    NSWorkspace.shared.open(AppLinks.paypal)
                }
            }
        }

        // Recording Controls Window (Standalone, single instance)
        Window("Recording", id: WindowID.recordingControls) {
            RecordingControlView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 480)

        // Preferences window — required for SettingsLink to work
        Settings {
            PreferencesView()
        }
    }
}
