//
//  ClaudeCodeBackend.swift
//  EngineKit
//
//  Runs the user's own, unmodified `claude` with their login, one process per turn, with Cameraman's MCP
//  server as its only tools. Anthropic allows this; it spends the plan's Agent SDK credit.
//  Flags and stream format: docs/RESEARCH/IN_APP_AGENT_2026-11.md.
//

import Foundation

public struct ClaudeCodeBackend: AgentBackend {
    public let name = "Claude Code"
    public let executable: URL
    public var model: String?

    public init(executable: URL, model: String? = nil) {
        self.executable = executable
        self.model = model
    }

    /// The installed `claude`: the usual install folders, then the login shell's PATH, since an app opened
    /// from Finder does not get the terminal's. The shell gets 3 s, so a slow or interactive rc cannot hang it.
    public static func locate() async -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let usual = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        if let found = executable(in: usual) { return found }
        let marker = "__CAMERAMAN_PATH__"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = try? await ProcessRun.run(URL(fileURLWithPath: shell), ["-ilc", "printf '\\n\(marker)%s' \"$PATH\""], timeout: 3)
        let loginPath = result?.output.components(separatedBy: marker).last?.split(separator: ":").map(String.init) ?? []
        return executable(in: loginPath)
    }

    private static func executable(in folders: [String]) -> URL? {
        folders.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func send(_ prompt: String, session: String?, context: AgentContext) -> AsyncStream<AgentEvent> {
        let arguments = { (config: URL) in Self.arguments(session: session, config: config, instructions: context.instructions, model: model) }
        let executable = executable
        return AsyncStream { continuation in
            let process = Process()
            let turn = Task.detached {
                let config = FileManager.default.temporaryDirectory.appendingPathComponent("cameraman-mcp-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: config) }
                do {
                    try Self.writeMCPConfig(context, to: config)
                    process.executableURL = executable
                    process.arguments = arguments(config)
                    process.currentDirectoryURL = AppDirectories.support
                    var parser = ClaudeStreamParser()
                    let result = try await ProcessRun.stream(process, input: Data(prompt.utf8)) { line in
                        parser.events(from: Data(line.utf8)).forEach { continuation.yield($0) }
                    }
                    if !parser.isDone && !Task.isCancelled {
                        let reason = result.errorTail.split(separator: "\n").last.map(String.init) ?? "exit code \(result.status)"
                        continuation.yield(.failed("Claude Code stopped: \(reason)"))
                    }
                } catch {
                    if !Task.isCancelled { continuation.yield(.failed("Could not start Claude Code: \(error.localizedDescription)")) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                turn.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Only Cameraman's tools, and nothing that would wait on a permission prompt nobody can answer.
    static func arguments(session: String?, config: URL, instructions: String, model: String?) -> [String] {
        var arguments = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                         "--mcp-config", config.path, "--strict-mcp-config",
                         "--tools", "", "--allowedTools", "mcp__cameraman", "--permission-mode", "dontAsk",
                         "--append-system-prompt", instructions]
        if let session { arguments += ["--resume", session] }
        if let model { arguments += ["--model", model] }
        return arguments
    }

    /// The token stays in a file only this user can read, not on the command line where `ps` shows it.
    static func writeMCPConfig(_ context: AgentContext, to url: URL) throws {
        let server: [String: Any] = ["type": "http", "url": context.mcpEndpoint.absoluteString,
                                     "headers": ["Authorization": "Bearer \(context.mcpToken)"]]
        let data = try JSONSerialization.data(withJSONObject: ["mcpServers": ["cameraman": server]])
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// Turns `claude --output-format stream-json` lines into events.
struct ClaudeStreamParser {
    private(set) var isDone = false
    private var hasText = false

    mutating func events(from line: Data) -> [AgentEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "system" where object["subtype"] as? String == "init":
            return (object["session_id"] as? String).map { [.started(session: $0)] } ?? []
        case "stream_event":
            return streamEvent(object["event"] as? [String: Any] ?? [:])
        case "assistant":
            return content(of: object).compactMap { block in
                guard block["type"] as? String == "tool_use", let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                return .toolStarted(id: id, name: name)
            }
        case "user":
            return content(of: object).compactMap { block in
                guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
                return .toolFinished(id: id, failed: block["is_error"] as? Bool ?? false)
            }
        case "result":
            isDone = true
            if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
                let reason = (object["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? object["subtype"] as? String ?? "unknown error"
                return [.failed(Self.isSignedOut(reason) ? Self.signInHint : reason)]
            }
            return [.finished(costUSD: object["total_cost_usd"] as? Double)]
        default:
            return []
        }
    }

    /// Text arrives as deltas; a new text block after earlier text starts a new paragraph.
    private mutating func streamEvent(_ event: [String: Any]) -> [AgentEvent] {
        switch event["type"] as? String {
        case "content_block_start":
            let block = event["content_block"] as? [String: Any]
            return block?["type"] as? String == "text" && hasText ? [.text("\n\n")] : []
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String, !text.isEmpty else { return [] }
            hasText = true
            return [.text(text)]
        default:
            return []
        }
    }

    static let signInHint = "Claude Code is not signed in. Run `claude auth login` in Terminal, then try again."

    static func isSignedOut(_ reason: String) -> Bool {
        let lowered = reason.lowercased()
        return lowered.contains("/login") || lowered.contains("not logged in") || lowered.contains("invalid api key")
    }

    private func content(of object: [String: Any]) -> [[String: Any]] {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }
}
