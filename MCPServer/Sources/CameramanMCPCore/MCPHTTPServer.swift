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
    private let expectedAuthorization: String
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "cameraman.mcp.http")
    private var listener: NWListener?

    public var port: UInt16 { listener?.port?.rawValue ?? 0 }

    /// - Parameter port: 0 picks a free port; read it back from `start()`.
    public init(server: MCPServer, token: String, port: UInt16 = 0) {
        self.server = server
        self.expectedAuthorization = "Bearer \(token)"
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

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() { cont.resume() }
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
        return port
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    /// Per-connection state, mutated only on `queue`.
    private final class Connection {
        let nw: NWConnection
        var buffer = Data()
        var head: HTTPRequest.Head?
        var bodyStart = 0
        init(_ nw: NWConnection) { self.nw = nw }
    }

    private var activeConnections = 0
    static let maxConnections = 32
    static let requestDeadline: TimeInterval = 10

    private func accept(_ nw: NWConnection) {
        guard activeConnections < Self.maxConnections else { nw.cancel(); return }
        activeConnections += 1
        let connection = Connection(nw)
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.queue.async { self?.activeConnections -= 1 }
            default: break
            }
        }
        nw.start(queue: queue)
        // A peer that connects and trickles (or sends nothing) must not hold a slot forever.
        queue.asyncAfter(deadline: .now() + Self.requestDeadline) { nw.cancel() }
        receive(connection)
    }

    private func receive(_ connection: Connection) {
        connection.nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { connection.buffer.append(data) }

            if connection.head == nil {
                switch HTTPRequest.parseHead(connection.buffer) {
                case .invalid(let status): return self.respond(connection.nw, status: status)
                case .needMore: break
                case .head(let head, let bodyStart):
                    // Reject before buffering a body from an unauthenticated peer.
                    if let status = self.reject(head) { return self.respond(connection.nw, status: status) }
                    connection.head = head
                    connection.bodyStart = bodyStart
                }
            }

            if let head = connection.head, connection.buffer.count - connection.bodyStart >= head.contentLength {
                let body = connection.buffer.subdata(in: connection.bodyStart..<(connection.bodyStart + head.contentLength))
                Task {
                    let reply = await self.dispatch(body)
                    self.respond(connection.nw, status: reply.status, body: reply.body)
                }
            } else if isComplete || error != nil {
                connection.nw.cancel()
            } else {
                self.receive(connection)
            }
        }
    }

    // MARK: - Routing

    struct Reply { var status: Int; var body: Data? }

    /// Status to refuse with, decided from the headers alone.
    func reject(_ head: HTTPRequest.Head) -> Int? {
        guard Self.isLoopbackHost(head.headers["host"]) else { return 403 }
        if let origin = head.headers["origin"], !Self.isLoopbackOrigin(origin) { return 403 }
        guard Self.constantTimeEqual(head.headers["authorization"] ?? "", expectedAuthorization) else { return 401 }
        guard head.path == Self.path else { return 404 }
        guard head.method == "POST" else { return 405 }
        return nil
    }

    func dispatch(_ body: Data) async -> Reply {
        guard let out = await server.handle(message: body) else {
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
        isLoopbackHost(URL(string: origin)?.host)
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
/// Header parsing is separate so a request can be refused before its body is read.
struct HTTPRequest {
    struct Head {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let contentLength: Int
    }

    enum HeadResult { case needMore, invalid(Int), head(Head, bodyStart: Int) }
    enum Parsed { case needMore, invalid(Int), request(Head, body: Data) }

    static func parseHead(_ data: Data) -> HeadResult {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > MCPHTTPServer.maxHeaderBytes ? .invalid(413) : .needMore
        }
        guard end.lowerBound <= MCPHTTPServer.maxHeaderBytes,
              let text = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .invalid(400) }

        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid(400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(400) }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid(400) } // only Content-Length

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid(400) }
        guard length <= MCPHTTPServer.maxBodyBytes else { return .invalid(413) }

        return .head(Head(method: String(requestLine[0]), path: String(requestLine[1]),
                          headers: headers, contentLength: length), bodyStart: end.upperBound)
    }

    static func parse(_ data: Data) -> Parsed {
        switch parseHead(data) {
        case .needMore: return .needMore
        case .invalid(let status): return .invalid(status)
        case .head(let head, let bodyStart):
            guard data.count - bodyStart >= head.contentLength else { return .needMore }
            return .request(head, body: data.subdata(in: bodyStart..<(bodyStart + head.contentLength)))
        }
    }
}
