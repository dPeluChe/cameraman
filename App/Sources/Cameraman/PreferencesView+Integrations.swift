//
//  PreferencesView+Integrations.swift
//  App
//
//  MCP integration, in order: allow connections (the in-app server), then pick a client and
//  copy its setup. Copy-paste snippets keep other apps' configs in the user's hands. The standalone binary stays as a folded, advanced option.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import EngineKit

struct IntegrationsPreferencesView: View {
    @ObservedObject private var host = MCPHostService.shared
    @AppStorage("mcp.host.enabled") private var hostEnabled = false
    @AppStorage("mcp.binaryPath") private var binaryPath = ""
    @State private var showBinaryPicker = false
    @State private var showStandalone = false
    @State private var selectedClient: MCPClient = .claudeCode

    /// External MCP clients we generate setup snippets for.
    private enum MCPClient: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
        case codex = "Codex CLI"
        case claudeDesktop = "Claude Desktop"
        var id: String { rawValue }

        var detail: String {
            switch self {
            case .claudeCode: "Run in your terminal"
            case .cursor: "Add to ~/.cursor/mcp.json"
            case .codex: "Add to ~/.codex/config.toml"
            case .claudeDesktop: "Add to ~/Library/Application Support/Claude/claude_desktop_config.json, then restart it"
            }
        }

        var note: String? {
            switch self {
            case .claudeCode: "Already added? Run claude mcp remove cameraman first. Restart Claude Code to load the tools."
            case .claudeDesktop: "Its config only starts local commands, so this goes through mcp-remote, which needs Node.js."
            case .cursor, .codex: nil
            }
        }
    }

    /// A binary is available (user-selected or bundled) — gates the standalone Copy button.
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

    /// The app's Projects directory, passed to the standalone server via CAMERAMAN_PROJECTS_DIR.
    private static let projectsDir = ProjectStore().baseDirectory.path

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Cameraman MCP Server")
                    .font(.headline)
                caption("Let AI assistants work on your projects: edit, add clips and effects, record, and place motion graphics.")
            }

            allowConnectionsSection
            connectClientSection
            standaloneSection

            Spacer()
        }
        .fileImporter(isPresented: $showBinaryPicker, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result { binaryPath = url.path }
        }
    }

    // MARK: - Steps

    private var allowConnectionsSection: some View {
        SettingsSection("1. Allow connections", spacing: Spacing.sm) {
            Toggle("Allow AI clients to connect on this Mac", isOn: $hostEnabled)
                .onChange(of: hostEnabled) { host.setEnabled($0) }
            switch host.state {
            case .stopped:
                caption("Off. Nothing is listening.")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            case .running:
                if let endpoint = host.endpoint {
                    Label("Listening on \(endpoint) (this Mac only, token required)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private var connectClientSection: some View {
        SettingsSection("2. Connect your client", spacing: Spacing.sm) {
            Picker("", selection: $selectedClient) {
                ForEach(MCPClient.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let endpoint = host.endpoint {
                clientRow(detail: selectedClient.detail, snippet: snippet(for: selectedClient, endpoint: endpoint))
                if let note = selectedClient.note { caption(note) }
                HStack {
                    caption("Treat the token like a password: anyone with it can edit your projects. Keep Cameraman open while the client works.")
                    Spacer()
                    Button("Regenerate token") { host.regenerateToken() }.controlSize(.small)
                }
            } else {
                caption("Turn on step 1 to see the setup for \(selectedClient.rawValue).")
            }
        }
    }

    private var standaloneSection: some View {
        DisclosureGroup("Advanced: standalone server", isExpanded: $showStandalone) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                caption("A separate binary for when Cameraman is closed. It cannot place motion graphics, and it does not pause the editor while it changes a project. Use the steps above unless you need this. Add one or the other, not both: they share the name cameraman.")
                binaryStatus
                clientRow(detail: selectedClient.detail, snippet: standaloneSnippet(for: selectedClient), enabled: hasBinary)
            }
            .padding(.top, Spacing.sm)
        }
        .font(.callout)
    }

    /// Bundled with the app, or the build-it-yourself fallback.
    @ViewBuilder
    private var binaryStatus: some View {
        if usingBundled {
            Label("Server bundled with the app.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            caption("Build it with: cd MCPServer && swift build -c release, then choose the binary at MCPServer/.build/release/cameraman-mcp.")
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Snippets

    private func snippet(for client: MCPClient, endpoint: String) -> String {
        switch client {
        case .claudeCode:
            "claude mcp add --scope user --transport http cameraman \(endpoint) --header \"Authorization: Bearer \(host.token)\""
        case .cursor:
            """
            {
              "mcpServers": {
                "cameraman": {
                  "url": "\(endpoint)",
                  "headers": { "Authorization": "Bearer \(host.token)" }
                }
              }
            }
            """
        case .codex:
            """
            [mcp_servers.cameraman]
            url = "\(endpoint)"

            [mcp_servers.cameraman.http_headers]
            Authorization = "Bearer \(host.token)"
            """
        case .claudeDesktop:
            """
            {
              "mcpServers": {
                "cameraman": {
                  "command": "npx",
                  "args": ["-y", "mcp-remote", "\(endpoint)", "--allow-http", "--header", "Authorization:${AUTH_HEADER}"],
                  "env": { "AUTH_HEADER": "Bearer \(host.token)" }
                }
              }
            }
            """
        }
    }

    private func standaloneSnippet(for client: MCPClient) -> String {
        switch client {
        case .claudeCode:
            "claude mcp add --scope user cameraman -e CAMERAMAN_PROJECTS_DIR=\"\(Self.projectsDir)\" -- \(resolvedPath)"
        case .cursor, .claudeDesktop:
            """
            {
              "mcpServers": {
                "cameraman": {
                  "command": "\(resolvedPath)",
                  "args": [],
                  "env": { "CAMERAMAN_PROJECTS_DIR": "\(Self.projectsDir)" }
                }
              }
            }
            """
        case .codex:
            """
            [mcp_servers.cameraman]
            command = "\(resolvedPath)"
            args = []
            env = { CAMERAMAN_PROJECTS_DIR = "\(Self.projectsDir)" }
            """
        }
    }

    @ViewBuilder
    private func clientRow(detail: String, snippet: String, enabled: Bool = true) -> some View {
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
                .disabled(!enabled)
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
