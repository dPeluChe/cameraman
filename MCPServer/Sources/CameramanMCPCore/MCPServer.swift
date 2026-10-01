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
    /// Revisions whose tools/list + tools/call shape we implement, newest first.
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// The client's version when we speak it, otherwise our newest (the client decides to go on).
    static func negotiate(_ requested: String?) -> String {
        guard let requested, supportedProtocolVersions.contains(requested) else {
            return supportedProtocolVersions[0]
        }
        return requested
    }
}

/// Protocol core, transport-agnostic: bytes in, bytes out. stdio and HTTP are thin
/// transports over `handle(message:)`. Requests are not serialized across a tool's
/// suspension points, so a slow export never blocks `ping`; tool state in `MCPTools`
/// must be safe for that (see its `activeRecording`).
public actor MCPServer {
    private let tools = MCPTools()

    public init() {}

    /// Read stdin line-by-line until EOF, dispatching each JSON-RPC message.
    public func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if var out = await handle(message: Data(trimmed.utf8)) {
                    out.append(0x0A) // newline frames the message
                    FileHandle.standardOutput.write(out)
                }
            }
        } catch {
            Self.log("read loop ended: \(error)")
        }
    }

    // MARK: - Dispatch

    /// One JSON-RPC message (or a batch) in, the serialized reply out. nil means
    /// nothing to send back (notifications, or a batch of only notifications).
    public func handle(message data: Data) async -> Data? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return Self.serialize(Self.errorReply(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = parsed as? [Any] {
            var replies: [[String: Any]] = []
            for item in batch {
                guard let object = item as? [String: Any] else {
                    replies.append(Self.errorReply(id: NSNull(), code: -32600, message: "Invalid Request"))
                    continue
                }
                if let reply = await process(object) { replies.append(reply) }
            }
            return replies.isEmpty ? nil : Self.serialize(replies)
        }
        guard let object = parsed as? [String: Any] else {
            return Self.serialize(Self.errorReply(id: NSNull(), code: -32600, message: "Invalid Request"))
        }
        return await process(object).flatMap { Self.serialize($0) }
    }

    private func process(_ object: [String: Any]) async -> [String: Any]? {
        let id = object["id"]   // absent (notification), number, string, or null
        let params = object["params"] as? [String: Any] ?? [:]
        // A response/garbage with no method is ignored.
        guard let method = object["method"] as? String else { return nil }
        // Notifications carry no id and never get a reply.
        let isNotification = (id == nil)
        let replyId = id ?? NSNull()

        switch method {
        case "initialize":
            return Self.result([
                "protocolVersion": MCPInfo.negotiate(params["protocolVersion"] as? String),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": MCPInfo.name, "version": MCPInfo.version]
            ], id: replyId)

        case "notifications/initialized", "initialized":
            return nil

        case "ping":
            return isNotification ? nil : Self.result([:], id: replyId)

        case "tools/list":
            return Self.result(["tools": MCPTools.catalog], id: replyId)

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let reply = await callTool(name: name, arguments: arguments, id: replyId)
            return isNotification ? nil : reply

        default:
            return isNotification ? nil : Self.errorReply(id: replyId, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Run a tool and report the result. Tool failures are returned as a
    /// successful JSON-RPC response with `isError: true` (per MCP convention),
    /// so the model sees the error text rather than a transport-level fault.
    private func callTool(name: String, arguments: [String: Any], id: Any) async -> [String: Any] {
        do {
            let text = try await tools.execute(name: name, arguments: arguments)
            return Self.result(["content": [["type": "text", "text": text]], "isError": false], id: id)
        } catch {
            // Prefer a human message: MCPToolError, then any LocalizedError
            // (e.g. EngineKit's ExportError), falling back to the raw value.
            let message = (error as? MCPToolError)?.message ?? error.localizedDescription
            Self.log("tool '\(name)' failed: \(message)")
            return Self.result(["content": [["type": "text", "text": "Error: \(message)"]], "isError": true], id: id)
        }
    }

    // MARK: - Output

    private static func result(_ result: [String: Any], id: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func errorReply(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func serialize(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("cameraman-mcp: \(message)\n".utf8))
    }
}
