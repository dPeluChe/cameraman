//
//  MCPServer.swift
//  cameraman-mcp
//
//  Minimal MCP server: reads newline-delimited JSON-RPC 2.0 from stdin, routes
//  the core methods (initialize / tools/list / tools/call / ping), and writes
//  responses to stdout. Notifications (no `id`) get no reply.
//

import Foundation

/// Server name/version advertised to MCP clients.
enum MCPInfo {
    static let name = "cameraman-mcp"
    static let version = "0.1.0"
    /// Protocol revision we implement; we echo the client's if it sends one.
    static let defaultProtocolVersion = "2024-11-05"
}

public final class MCPServer {
    private let tools = MCPTools()

    public init() {}

    /// Read stdin line-by-line until EOF, dispatching each JSON-RPC message.
    public func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                await handle(line: trimmed)
            }
        } catch {
            log("read loop ended: \(error)")
        }
    }

    // MARK: - Dispatch

    private func handle(line: String) async {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            send(errorId: NSNull(), code: -32700, message: "Parse error")
            return
        }

        let method = object["method"] as? String
        let id = object["id"]   // may be absent (notification), number, string, or null
        let params = object["params"] as? [String: Any] ?? [:]

        guard let method = method else {
            // A response/garbage with no method — ignore.
            return
        }

        // Notifications carry no id and never get a reply.
        let isNotification = (id == nil)

        switch method {
        case "initialize":
            let clientVersion = params["protocolVersion"] as? String
            let result: [String: Any] = [
                "protocolVersion": clientVersion ?? MCPInfo.defaultProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": MCPInfo.name, "version": MCPInfo.version]
            ]
            send(result: result, id: id ?? NSNull())

        case "notifications/initialized", "initialized":
            break // notification, no reply

        case "ping":
            if !isNotification { send(result: [:], id: id ?? NSNull()) }

        case "tools/list":
            send(result: ["tools": MCPTools.catalog], id: id ?? NSNull())

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            await callTool(name: name, arguments: arguments, id: id ?? NSNull(), isNotification: isNotification)

        default:
            if !isNotification {
                send(errorId: id ?? NSNull(), code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    /// Run a tool and report the result. Tool failures are returned as a
    /// successful JSON-RPC response with `isError: true` (per MCP convention),
    /// so the model sees the error text rather than a transport-level fault.
    private func callTool(name: String, arguments: [String: Any], id: Any, isNotification: Bool) async {
        do {
            let text = try await tools.execute(name: name, arguments: arguments)
            guard !isNotification else { return }
            send(result: [
                "content": [["type": "text", "text": text]],
                "isError": false
            ], id: id)
        } catch {
            let message = (error as? MCPToolError)?.message ?? "\(error)"
            log("tool '\(name)' failed: \(message)")
            guard !isNotification else { return }
            send(result: [
                "content": [["type": "text", "text": "Error: \(message)"]],
                "isError": true
            ], id: id)
        }
    }

    // MARK: - Output

    private func send(result: [String: Any], id: Any) {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func send(errorId id: Any, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var line = data
        line.append(0x0A) // newline frames the message
        FileHandle.standardOutput.write(line)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("cameraman-mcp: \(message)\n".utf8))
    }
}
