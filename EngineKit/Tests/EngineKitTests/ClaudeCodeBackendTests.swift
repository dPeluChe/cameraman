import XCTest
@testable import EngineKit

final class ClaudeCodeBackendTests: XCTestCase {
    private func events(_ lines: [String]) -> [AgentEvent] {
        var parser = ClaudeStreamParser()
        return lines.flatMap { parser.events(from: Data($0.utf8)) }
    }

    func testATurnWithAToolCallBecomesEvents() {
        let lines = [
            #"{"type":"system","subtype":"hook_started","session_id":"s1"}"#,
            #"{"type":"system","subtype":"init","session_id":"s1","apiKeySource":"none"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Voy a ver"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" el proyecto."}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Voy a ver el proyecto."},{"type":"tool_use","id":"t1","name":"mcp__cameraman__get_project","input":{}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"{}","is_error":false}]}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Listo."}}}"#,
            #"{"type":"rate_limit_event","rate_limit_info":{}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"Listo.","total_cost_usd":0.012,"session_id":"s1"}"#,
            "not json",
        ]
        XCTAssertEqual(events(lines), [
            .started(session: "s1"),
            .text("Voy a ver"), .text(" el proyecto."),
            .toolStarted(id: "t1", name: "mcp__cameraman__get_project"),
            .toolFinished(id: "t1", failed: false),
            .text("\n\n"), .text("Listo."),
            .finished(costUSD: 0.012),
        ])
    }

    func testAnErrorResultFails() {
        let lines = [#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#]
        XCTAssertEqual(events(lines), [.failed("Not logged in · Please run /login")])
        XCTAssertEqual(events([#"{"type":"result","subtype":"error_max_turns","is_error":false}"#]), [.failed("error_max_turns")])
    }

    func testOnlyCameramanToolsAndNoPromptsAndTheTokenIsNotOnTheCommandLine() throws {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: config) }
        let context = AgentContext(mcpEndpoint: URL(string: "http://127.0.0.1:8765/mcp")!, mcpToken: "secret", instructions: "Be brief")
        try ClaudeCodeBackend.writeMCPConfig(context, to: config)

        let permissions = try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let server = try XCTUnwrap((written["mcpServers"] as? [String: Any])?["cameraman"] as? [String: Any])
        XCTAssertEqual(server["url"] as? String, "http://127.0.0.1:8765/mcp")
        XCTAssertEqual((server["headers"] as? [String: String])?["Authorization"], "Bearer secret")

        let arguments = ClaudeCodeBackend.arguments(session: "s1", config: config, instructions: "Be brief", model: nil)
        XCTAssertFalse(arguments.contains { $0.contains("secret") })
        for flag in ["--strict-mcp-config", "-p"] { XCTAssertTrue(arguments.contains(flag), flag) }
        let pairs = Dictionary(zip(arguments, arguments.dropFirst()), uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(pairs["--tools"], "")
        XCTAssertEqual(pairs["--allowedTools"], "mcp__cameraman")
        XCTAssertEqual(pairs["--permission-mode"], "dontAsk")
        XCTAssertEqual(pairs["--resume"], "s1")
        XCTAssertNil(pairs["--model"])
    }

    /// Spends a few cents of the local user's plan, so it only runs when asked: CAMERAMAN_AGENT_E2E=1.
    func testTheInstalledClaudeAnswersAndContinuesItsSession() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAMERAMAN_AGENT_E2E"] == "1")
        let located = await ClaudeCodeBackend.locate()
        let executable = try XCTUnwrap(located, "claude is not installed")
        let backend = ClaudeCodeBackend(executable: executable, model: "haiku")
        let context = AgentContext(mcpEndpoint: URL(string: "http://127.0.0.1:9/mcp")!, mcpToken: "none",
                                   instructions: "Answer with one word.")

        var first: [AgentEvent] = []
        for await event in backend.send("Say: hola", session: nil, context: context) { first.append(event) }
        guard case .started(let session)? = first.first else { return XCTFail("\(first)") }
        guard case .finished? = first.last else { return XCTFail("\(first)") }

        var second: [AgentEvent] = []
        for await event in backend.send("Repeat your last word", session: session, context: context) { second.append(event) }
        guard case .finished? = second.last else { return XCTFail("\(second)") }
        let text = second.compactMap { if case .text(let piece) = $0 { return piece } else { return nil } }.joined()
        XCTAssertTrue(text.lowercased().contains("hola"), text)
    }
}
