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

    private var resolvedPath: String {
        binaryPath.isEmpty ? "/path/to/cameraman-mcp" : binaryPath
    }

    private var binaryExists: Bool {
        !binaryPath.isEmpty && FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cameraman MCP Server")
                    .font(.headline)
                Text("Expose Cameraman's tools (list/create projects, record, split, add clips, effects) to AI assistants over MCP. Build the server, point to the binary, then paste the snippet into each client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Build instructions
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Build the server")
                    .font(.subheadline.weight(.semibold))
                snippetBox("cd MCPServer && swift build -c release")
                Text("Produces the binary at MCPServer/.build/release/cameraman-mcp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Binary path
            VStack(alignment: .leading, spacing: 6) {
                Text("2. Locate the binary")
                    .font(.subheadline.weight(.semibold))
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

            // Client snippets
            VStack(alignment: .leading, spacing: 6) {
                Text("3. Register with a client")
                    .font(.subheadline.weight(.semibold))

                clientRow(
                    "Claude Desktop",
                    detail: "Add to ~/Library/Application Support/Claude/claude_desktop_config.json",
                    snippet: claudeJSONSnippet
                )
                clientRow(
                    "Claude Code",
                    detail: "Run in your terminal",
                    snippet: "claude mcp add cameraman -- \(resolvedPath)"
                )
                clientRow(
                    "Codex CLI",
                    detail: "Add to ~/.codex/config.toml",
                    snippet: codexTOMLSnippet
                )
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
            "cameraman": { "command": "\(resolvedPath)", "args": [] }
          }
        }
        """
    }

    private var codexTOMLSnippet: String {
        """
        [mcp_servers.cameraman]
        command = "\(resolvedPath)"
        args = []
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
