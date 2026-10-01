//
//  MCPHTTPServer.swift
//  cameraman-mcp
//
//  Loopback HTTP transport for MCPServer (MCP "Streamable HTTP", JSON responses only).
//  Lets the app host the server in-process, which is the only shape that works under
//  the Mac App Store sandbox (a helper launched by another app cannot inherit it).
//
//  Hardening, because any local process or web page can reach 127.0.0.1:
//  - bound to loopback only
//  - bearer token required on every request
//  - Host must be loopback (blocks DNS rebinding); Origin, if sent, must be loopback
//  - body and header size caps
//

import Foundation
import Network

public final class MCPHTTPServer: @unchecked Sendable {
    public enum StartError: Error { case invalidPort, failed(String) }

    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 8 * 1024 * 1024
    static let path = "/mcp"

    private let server: MCPServer
    private let token: String
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "cameraman.mcp.http")
    private var listener: NWListener?

    public private(set) var port: UInt16 = 0

    /// - Parameter port: 0 picks a free port; read it back from `start()`.
    public init(server: MCPServer, token: String, port: UInt16 = 0) {
        self.server = server
        self.token = token
        self.requestedPort = port
    }

    /// Starts listening and returns the bound port.
    @discardableResult
    public func start() async throws -> UInt16 {
        guard listener == nil else { return port }
        let params = NWParameters.tcp
        let endpointPort: NWEndpoint.Port
        if requestedPort == 0 {
            endpointPort = .any
        } else if let p = NWEndpoint.Port(rawValue: requestedPort) {
            endpointPort = p
        } else {
            throw StartError.invalidPort
        }
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)

        let listener: NWListener
        do { listener = try NWListener(using: params) } catch { throw StartError.failed("\(error)") }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let bound: UInt16 = try await withCheckedThrowingContinuation { cont in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if resumed.claim() { cont.resume(throwing: StartError.failed("\(error)")) }
                case .cancelled:
                    if resumed.claim() { cont.resume(throwing: StartError.failed("cancelled")) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        self.port = bound
        return bound
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPRequest.parse(buffer) {
            case .needMore:
                if isComplete || error != nil { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
            case .invalid(let status):
                self.respond(connection, status: status)
            case .request(let request):
                Task { [server = self.server] in
                    let response = await self.route(request, server: server)
                    self.respond(connection, status: response.status, body: response.body)
                }
            }
        }
    }

    // MARK: - Routing

    struct Reply { var status: Int; var body: Data? }

    func route(_ request: HTTPRequest, server: MCPServer) async -> Reply {
        guard Self.isLoopbackHost(request.headers["host"]) else { return Reply(status: 403, body: nil) }
        if let origin = request.headers["origin"], !Self.isLoopbackOrigin(origin) {
            return Reply(status: 403, body: nil)
        }
        guard Self.constantTimeEqual(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return Reply(status: 401, body: nil)
        }
        guard request.path == Self.path else { return Reply(status: 404, body: nil) }
        guard request.method == "POST" else { return Reply(status: 405, body: nil) }

        guard let out = await server.handle(message: request.body) else {
            return Reply(status: 202, body: nil) // notification: accepted, no content
        }
        return Reply(status: 200, body: out)
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data? = nil) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\nConnection: close\r\n"
        if let body {
            head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        if status == 405 { head += "Allow: POST\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        if let body { out.append(body) }
        connection.send(content: out, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Helpers

    static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        return name == "127.0.0.1" || name == "localhost"
    }

    static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let host = URL(string: origin)?.host else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Minimal HTTP/1.1 request parser: request line, headers, Content-Length body.
struct HTTPRequest {
    enum Parsed { case needMore, invalid(Int), request(HTTPRequest) }

    let method: String
    let path: String
    let headers: [String: String]   // lowercased names
    let body: Data

    static func parse(_ data: Data) -> Parsed {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > MCPHTTPServer.maxHeaderBytes ? .invalid(413) : .needMore
        }
        guard end.lowerBound <= MCPHTTPServer.maxHeaderBytes,
              let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .invalid(400) }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid(400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(400) }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid(400) } // only Content-Length

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid(400) }
        guard length <= MCPHTTPServer.maxBodyBytes else { return .invalid(413) }

        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return .needMore }
        let body = data[bodyStart..<(bodyStart + length)]
        return .request(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]),
                                    headers: headers, body: Data(body)))
    }
}
