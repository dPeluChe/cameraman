//
//  PreferencesView+Integrations.swift
//  App
//
//  MCP integration: register the cameraman-mcp stdio server with external
//  clients (Claude Desktop, Claude Code, Codex). The app is sandboxed and
//  cannot write other apps' configs, so we generate copy-paste snippets.
//

import SwiftUI
import UniformTypeIdentifiers
import EngineKit

struct IntegrationsPreferencesView: View {
    @AppStorage("mcp.binaryPath") private var binaryPath = ""
    @State private var showBinaryPicker = false
    @State private var selectedClient: MCPClient = .claudeDesktop

    /// External MCP clients we generate registration snippets for.
    private enum MCPClient: String, CaseIterable, Identifiable {
        case claudeDesktop = "Claude Desktop"
        case claudeCode = "Claude Code"
        case codex = "Codex CLI"
        var id: String { rawValue }

        var detail: String {
            switch self {
            case .claudeDesktop: "Add to ~/Library/Application Support/Claude/claude_desktop_config.json"
            case .claudeCode: "Run in your terminal"
            case .codex: "Add to ~/.codex/config.toml"
            }
        }
    }

    /// A binary is available (user-selected or bundled) — gates the Copy buttons.
    private var hasBinary: Bool { !binaryPath.isEmpty || bundledPath != nil }

    /// The MCP binary shipped inside the app bundle (Contents/Helpers), if present.
    private var bundledPath: String? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cameraman-mcp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    /// Path used in the snippets: user override wins, else the bundled binary,
    /// else a placeholder for the build-it-yourself flow.
    private var resolvedPath: String {
        if !binaryPath.isEmpty { return binaryPath }
        return bundledPath ?? "/path/to/cameraman-mcp"
    }

    private var usingBundled: Bool { binaryPath.isEmpty && bundledPath != nil }

    private var binaryExists: Bool {
        !binaryPath.isEmpty && FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    /// This (sandboxed) app's Projects directory — the MCP server must be pointed
    /// here via CAMERAMAN_PROJECTS_DIR or it reads a different, empty folder.
    private var projectsDir: String { ProjectStore().baseDirectory.path }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Cameraman MCP Server")
                    .font(.headline)
                Text("Expose Cameraman's tools (list/create projects, record, split, add clips, effects) to AI assistants over MCP. Copy the snippet for your client and paste it in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Binary status — bundled with the app, or build-it-yourself fallback
            SettingsSection("Server binary", spacing: Spacing.sm) {
                if usingBundled {
                    Label("Server bundled with the app — ready to use.", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text("Build it with: cd MCPServer && swift build -c release, then choose the binary at MCPServer/.build/release/cameraman-mcp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Image(systemName: binaryExists ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(binaryExists ? .green : .secondary)
                        Text(binaryPath.isEmpty ? "No binary selected" : binaryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { showBinaryPicker = true }
                            .controlSize(.small)
                    }
                }
                if !binaryPath.isEmpty {
                    Button("Use bundled binary") { binaryPath = "" }
                        .controlSize(.small)
                        .disabled(bundledPath == nil)
                }
            }

            // Client snippets — one tab per client, only the selected one shown
            SettingsSection("Register with a client", spacing: Spacing.sm) {
                Picker("", selection: $selectedClient) {
                    ForEach(MCPClient.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                clientRow(detail: selectedClient.detail, snippet: snippet(for: selectedClient))

                Text("Snippets point the server at this app's projects via CAMERAMAN_PROJECTS_DIR, so it sees the same projects you edit here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .fileImporter(isPresented: $showBinaryPicker, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result { binaryPath = url.path }
        }
    }

    // MARK: - Snippets

    private var claudeJSONSnippet: String {
        """
        {
          "mcpServers": {
            "cameraman": {
              "command": "\(resolvedPath)",
              "args": [],
              "env": { "CAMERAMAN_PROJECTS_DIR": "\(projectsDir)" }
            }
          }
        }
        """
    }

    private var codexTOMLSnippet: String {
        """
        [mcp_servers.cameraman]
        command = "\(resolvedPath)"
        args = []
        env = { CAMERAMAN_PROJECTS_DIR = "\(projectsDir)" }
        """
    }

    private func snippet(for client: MCPClient) -> String {
        switch client {
        case .claudeDesktop: claudeJSONSnippet
        case .claudeCode: "claude mcp add cameraman -e CAMERAMAN_PROJECTS_DIR=\"\(projectsDir)\" -- \(resolvedPath)"
        case .codex: codexTOMLSnippet
        }
    }

    @ViewBuilder
    private func clientRow(detail: String, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(!hasBinary)
            }
            snippetBox(snippet)
        }
        .padding(.vertical, 4)
    }

    private func snippetBox(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}
