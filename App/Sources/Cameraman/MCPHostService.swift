//
//  MCPHostService.swift
//  App
//
//  Hosts the MCP server inside the app (loopback HTTP), so clients and the in-app assistant
//  reach the open editor. Opt-in: nothing listens until the user turns it on.
//

import Combine
import EngineKit
import Foundation
import Security
import CameramanMCPCore

@MainActor
final class MCPHostService: ObservableObject {
    enum State: Equatable { case stopped, running(port: UInt16), failed(String) }

    static let shared = MCPHostService()
    static let defaultPort: UInt16 = 8765

    private static let enabledKey = "mcp.host.enabled"
    private static let keychainService = "dev.dpeluche.CameramanApp.mcp"

    @Published private(set) var state: State = .stopped
    /// Empty until the server first starts, so the Keychain is untouched while the feature is off.
    @Published private(set) var token = ""

    private var http: MCPHTTPServer?
    /// The bind in flight, so overlapping starts (launch, Preferences, the assistant) share one listener.
    private var starting: Task<Void, Never>?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    var endpoint: String? {
        guard case .running(let port) = state else { return nil }
        return "http://127.0.0.1:\(port)/mcp"
    }

    private init() {}

    func startIfEnabled() {
        if isEnabled { Task { await start() } }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { Task { await start() } } else { stop() }
    }

    /// Turns the server on for the in-app assistant. Nil when the port is taken.
    func ensureRunning() async -> (endpoint: URL, token: String)? {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await start()
        return endpoint.flatMap(URL.init(string:)).map { ($0, token) }
    }

    func start() async {
        if let starting { return await starting.value }
        guard http == nil else { return }
        let task = Task { await bind() }
        starting = task
        await task.value
        starting = nil
    }

    private func bind() async {
        if token.isEmpty { token = Self.loadOrCreateToken() }
        let port = Self.defaultPort
        let server = MCPHTTPServer(server: Self.makeServer(), token: token, port: port)
        do {
            let bound = try await server.start()
            // Turned off while the listener was coming up.
            guard isEnabled else { server.stop(); return }
            http = server
            state = .running(port: bound)
            LogInfo(.ui, "[MCP] in-app server listening on 127.0.0.1:\(bound)")
        } catch {
            // No silent fallback to another port: it would break every pasted client config.
            state = .failed("Port \(port) is unavailable. Close what is using it and turn this on again.")
            LogError(.ui, "[MCP] could not listen on port \(port): \(error)")
        }
    }

    /// MCP edits go straight to disk. AgentActivityCenter freezes the open editor, flushes its
    /// unsaved work first, and reloads once the agent goes quiet.
    private static func makeServer() -> MCPServer {
        MCPServer(
            supportsRendering: true,
            onProjectChanged: { id in Task { @MainActor in AgentActivityCenter.shared.agentDidEdit(id) } },
            onProjectWillChange: { id in await AgentActivityCenter.shared.agentWillEdit(id) }
        )
    }

    func stop() {
        http?.stop()
        http = nil
        state = .stopped
    }

    /// New token invalidates every client config; restart so the listener uses it.
    func regenerateToken() {
        let wasRunning = http != nil
        stop()
        token = Self.storeNewToken()
        if wasRunning { Task { await start() } }
    }

    // MARK: - Keychain

    private static func loadOrCreateToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "token",
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let value = String(data: data, encoding: .utf8) {
            return value
        }
        return storeNewToken()
    }

    private static func storeNewToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.map { String(format: "%02x", $0) }.joined()

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "token",
        ]
        SecItemDelete(identity as CFDictionary)
        var add = identity
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { LogError(.ui, "[MCP] could not store token in Keychain (\(status))") }
        return value
    }
}
