//
//  AISuggestionsView.swift
//  App
//
//  "AI Assistant (MCP)" hub: instead of weak local heuristics, point the user
//  at Cameraman's MCP server so their AI assistant (Claude/Codex) can edit the
//  project for them — cut silences, add chapters, caption, apply effects, export.
//

import SwiftUI
import AppKit
import EngineKit

struct AISuggestionsView: View {
    @ObservedObject var editor: ProjectEditor
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?

    private var projectName: String { editor.project.name }

    /// The MCP binary ships inside the app bundle; a user-picked path also counts.
    private var mcpReady: Bool {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cameraman-mcp")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return true }
        let custom = UserDefaults.standard.string(forKey: "mcp.binaryPath") ?? ""
        return !custom.isEmpty && FileManager.default.isExecutableFile(atPath: custom)
    }

    private var prompts: [String] {
        [
            "In my Cameraman project “\(projectName)”, remove the silent pauses.",
            "Transcribe “\(projectName)” in Spanish and add the captions to the timeline.",
            "Suggest chapters for “\(projectName)” from its transcript and apply them.",
            "Apply black & white to the screen for the first 5 seconds of “\(projectName)”.",
            "Export “\(projectName)” as web 1080p H.264 when you're done.",
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("AI Assistant (MCP)") {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    intro
                    connectionSection
                    promptsSection
                }
                .padding(Spacing.xl)
            }
        }
        .modalFrame(.large)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Edit this project with your AI assistant", systemImage: "sparkles")
                .font(.headline)
            Text("Cameraman runs a local MCP server, so assistants like Claude (Desktop/Code) and Codex can edit this project for you — cut silences, add chapters, generate captions, apply effects, and export. Just ask, in plain language.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionSection: some View {
        SettingsSection("Connection") {
            if mcpReady {
                Label("MCP server bundled and ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Register the MCP server with your assistant to get started.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Button("Open Settings → Developer") { openSettings() }
                .controlSize(.small)

            Text("Your assistant sees the same project library, so it can open “\(projectName)” by name.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptsSection: some View {
        SettingsSection("Try asking your assistant") {
            ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(prompt)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(copied == prompt ? "Copied" : "Copy") {
                        Clipboard.copy(prompt)
                        copied = prompt
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, Spacing.xs)

                if index < prompts.count - 1 { Divider() }
            }
        }
    }

    /// Open the Settings window (selector name differs across macOS versions).
    private func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
