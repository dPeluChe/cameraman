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

    /// The installed `claude`: the usual install folders first, then the login shell's PATH, since an app
    /// opened from Finder does not get the terminal's.
    public static func locate() async -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let usual = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        let marker = "__CAMERAMAN_PATH__"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let output = await run(URL(fileURLWithPath: shell), ["-ilc", "printf '\\n\(marker)%s' \"$PATH\""])
        let loginPath = output?.components(separatedBy: marker).last?.split(separator: ":").map(String.init) ?? []
        return (usual + loginPath).lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func send(_ prompt: String, session: String?, context: AgentContext) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let process = Process()
            let config = FileManager.default.temporaryDirectory.appendingPathComponent("cameraman-mcp-\(UUID().uuidString).json")
            let finish = { (event: AgentEvent) in
                continuation.yield(event)
                continuation.finish()
            }
            do {
                try Self.writeMCPConfig(context, to: config)
            } catch {
                return finish(.failed("Could not prepare the connection to Cameraman: \(error.localizedDescription)"))
            }

            let input = Pipe(), output = Pipe(), errors = Pipe()
            process.executableURL = executable
            process.arguments = Self.arguments(session: session, config: config, instructions: context.instructions, model: model)
            process.currentDirectoryURL = AppDirectories.support
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            let reader = Task {
                var parser = ClaudeStreamParser()
                do {
                    for try await line in output.fileHandleForReading.bytes.lines {
                        parser.events(from: Data(line.utf8)).forEach { continuation.yield($0) }
                    }
                } catch {}
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: config)
                if !parser.isDone {
                    let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let reason = stderr.split(separator: "\n").last.map(String.init) ?? "exit code \(process.terminationStatus)"
                    continuation.yield(.failed(Task.isCancelled ? "Stopped." : "Claude Code stopped: \(reason)"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                reader.cancel()
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            } catch {
                reader.cancel()
                try? FileManager.default.removeItem(at: config)
                finish(.failed("Could not start Claude Code: \(error.localizedDescription)"))
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
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func run(_ executable: URL, _ arguments: [String]) async -> String? {
        await Task.detached {
            let process = Process(), output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
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
                return [.failed(reason)]
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

    private func content(of object: [String: Any]) -> [[String: Any]] {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }
}
