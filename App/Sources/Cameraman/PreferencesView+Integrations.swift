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

struct IntegrationsPreferencesView: View {
    @AppStorage("mcp.binaryPath") private var binaryPath = ""
    @State private var showBinaryPicker = false

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
    private var projectsDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ProjectStudio/Projects", isDirectory: true).path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cameraman MCP Server")
                    .font(.headline)
                Text("Expose Cameraman's tools (list/create projects, record, split, add clips, effects) to AI assistants over MCP. Copy the snippet for your client and paste it in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Binary status — bundled with the app, or build-it-yourself fallback
            VStack(alignment: .leading, spacing: 6) {
                if usingBundled {
                    Label("Server bundled with the app — ready to use.", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text("Server binary")
                        .font(.subheadline.weight(.semibold))
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

            // Client snippets
            VStack(alignment: .leading, spacing: 6) {
                Text("Register with a client")
                    .font(.subheadline.weight(.semibold))

                clientRow(
                    "Claude Desktop",
                    detail: "Add to ~/Library/Application Support/Claude/claude_desktop_config.json",
                    snippet: claudeJSONSnippet
                )
                clientRow(
                    "Claude Code",
                    detail: "Run in your terminal",
                    snippet: "claude mcp add cameraman -e CAMERAMAN_PROJECTS_DIR=\"\(projectsDir)\" -- \(resolvedPath)"
                )
                clientRow(
                    "Codex CLI",
                    detail: "Add to ~/.codex/config.toml",
                    snippet: codexTOMLSnippet
                )

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

    @ViewBuilder
    private func clientRow(_ name: String, detail: String, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.callout.weight(.medium))
                Spacer()
                Button {
                    Clipboard.copy(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(binaryPath.isEmpty)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
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
