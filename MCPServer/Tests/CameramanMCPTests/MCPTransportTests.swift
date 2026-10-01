import XCTest
@testable import CameramanMCPCore

final class MCPProtocolTests: XCTestCase {
    private func call(_ server: MCPServer, _ json: String) async -> [String: Any]? {
        guard let out = await server.handle(message: Data(json.utf8)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
    }

    func testInitializeEchoesClientVersion() async throws {
        let replyRaw = await call(MCPServer(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        let reply = try XCTUnwrap(replyRaw)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
    }

    func testUnknownProtocolVersionFallsBackToNewestSupported() {
        XCTAssertEqual(MCPInfo.negotiate("2099-01-01"), MCPInfo.supportedProtocolVersions[0])
        XCTAssertEqual(MCPInfo.negotiate("2024-11-05"), "2024-11-05")
        XCTAssertEqual(MCPInfo.negotiate(nil), MCPInfo.supportedProtocolVersions[0])
    }

    func testNotificationGetsNoReply() async {
        let reply = await call(MCPServer(), #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(reply)
    }

    func testParseErrorAndUnknownMethod() async throws {
        let badRaw = await call(MCPServer(), "{nope")
        let bad = try XCTUnwrap(badRaw)
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32700)
        let unknownRaw = await call(MCPServer(), #"{"jsonrpc":"2.0","id":2,"method":"nope"}"#)
        let unknown = try XCTUnwrap(unknownRaw)
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testBatchSkipsNotifications() async throws {
        let outRaw = await MCPServer().handle(message: Data(#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"initialized"}]"#.utf8))
        let out = try XCTUnwrap(outRaw)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: out) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
    }
}

final class MCPHTTPServerTests: XCTestCase {
    private let token = "test-token"
    private var http: MCPHTTPServer!
    private var base: URL!

    override func setUp() async throws {
        http = MCPHTTPServer(server: MCPServer(), token: token)
        let port = try await http.start()
        base = URL(string: "http://127.0.0.1:\(port)/mcp")!
    }

    override func tearDown() async throws { http.stop() }

    private func post(_ body: String, token: String? = "test-token", extra: [String: String] = [:]) async throws -> (Int, Data) {
        var request = URLRequest(url: base)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in extra { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    func testToolsListOverHTTP() async throws {
        let (status, data) = try await post(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        XCTAssertEqual(status, 200)
        let reply = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertFalse(tools.isEmpty)
    }

    func testMissingOrWrongTokenIs401() async throws {
        let none = try await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, token: nil)
        XCTAssertEqual(none.0, 401)
        let wrong = try await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, token: "nope")
        XCTAssertEqual(wrong.0, 401)
    }

    func testNotificationIs202() async throws {
        let (status, data) = try await post(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(status, 202)
        XCTAssertTrue(data.isEmpty)
    }

    func testForeignOriginIs403() async throws {
        let (status, _) = try await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, extra: ["Origin": "https://evil.example"])
        XCTAssertEqual(status, 403)
    }

    func testRefusedFromHeadersAloneBeforeBodyIsRead() {
        let head = HTTPRequest.Head(method: "POST", path: "/mcp",
                                    headers: ["host": "127.0.0.1:1", "content-length": "8388608"],
                                    contentLength: 8_388_608)
        XCTAssertEqual(http.reject(head), 401) // no token, no body needed to decide
    }

    func testGetIs405() async throws {
        var request = URLRequest(url: base)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 405)
    }

    func testHostCheckRejectsNonLoopback() {
        XCTAssertTrue(MCPHTTPServer.isLoopbackHost("127.0.0.1:8890"))
        XCTAssertTrue(MCPHTTPServer.isLoopbackHost("localhost"))
        XCTAssertFalse(MCPHTTPServer.isLoopbackHost("evil.example"))
        XCTAssertFalse(MCPHTTPServer.isLoopbackHost(nil))
    }

    func testParserWaitsForFullBodyAndRejectsChunked() {
        let partial = Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)
        if case .needMore = HTTPRequest.parse(partial) {} else { XCTFail("expected needMore") }
        let chunked = Data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        if case .invalid(400) = HTTPRequest.parse(chunked) {} else { XCTFail("expected 400") }
    }
}
