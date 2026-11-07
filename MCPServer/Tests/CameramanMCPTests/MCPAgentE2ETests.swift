//
//  Claude Code reaching the HTTP server with its token and calling a tool, as the in-app assistant does.
//  Spends a few cents of the local user's plan, so it only runs when asked: CAMERAMAN_AGENT_E2E=1.
//

import XCTest
import EngineKit
@testable import CameramanMCPCore

final class MCPAgentE2ETests: XCTestCase {
    func testClaudeCodeCallsCameramanToolsOverHTTP() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAMERAMAN_AGENT_E2E"] == "1")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agent-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        setenv("CAMERAMAN_PROJECTS_DIR", scratch.path, 1)

        let token = UUID().uuidString
        let http = MCPHTTPServer(server: MCPServer(), token: token)
        let port = try await http.start()
        defer { http.stop() }

        let located = await ClaudeCodeBackend.locate()
        let backend = ClaudeCodeBackend(executable: try XCTUnwrap(located), model: "haiku")
        let context = AgentContext(mcpEndpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!, mcpToken: token,
                                   instructions: "Use the cameraman tools.")
        var events: [AgentEvent] = []
        for await event in backend.send("Call list_projects once and tell me how many projects there are.", session: nil, context: context) {
            events.append(event)
        }
        let tools = events.compactMap { if case .toolStarted(_, let name) = $0 { return name } else { return nil } }
        XCTAssertTrue(tools.contains("mcp__cameraman__list_projects"), "\(events)")
        XCTAssertTrue(events.contains { if case .toolFinished(_, false) = $0 { return true } else { return false } }, "\(events)")
        guard case .finished? = events.last else { return XCTFail("\(events)") }
    }
}
