//
//  MCPHostService.swift
//  App
//
//  Hosts the MCP server inside the app (loopback HTTP) so the same build works in the
//  Mac App Store sandbox, where a helper launched by another app cannot run. Opt-in:
//  nothing listens until the user turns it on.
//

import Combine
import Foundation
import os
import Security
import CameramanMCPCore

@MainActor
final class MCPHostService: ObservableObject {
    enum State: Equatable { case stopped, running(port: UInt16), failed(String) }

    static let shared = MCPHostService()
    static let defaultPort: UInt16 = 8765

    private static let enabledKey = "mcp.host.enabled"
    private static let portKey = "mcp.host.port"
    private static let keychainService = "dev.dpeluche.CameramanApp.mcp"

    @Published private(set) var state: State = .stopped
    @Published private(set) var token: String

    private var http: MCPHTTPServer?
    private let log = Logger(subsystem: "dev.dpeluche.CameramanApp", category: "mcp-host")

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    var endpoint: String? {
        guard case .running(let port) = state else { return nil }
        return "http://127.0.0.1:\(port)/mcp"
    }

    private init() {
        token = Self.loadOrCreateToken()
    }

    func startIfEnabled() {
        log.info("startIfEnabled enabled=\(self.isEnabled, privacy: .public)")
        if isEnabled { Task { await start() } }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { Task { await start() } } else { stop() }
    }

    func start() async {
        guard http == nil else { return }
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        let preferred = UInt16(exactly: stored).flatMap { $0 == 0 ? nil : $0 } ?? Self.defaultPort
        // Keep the port stable so client configs stay valid; fall back to any free port.
        for port in [preferred, 0] {
            let server = MCPHTTPServer(server: MCPServer(), token: token, port: port)
            do {
                let bound = try await server.start()
                http = server
                UserDefaults.standard.set(Int(bound), forKey: Self.portKey)
                state = .running(port: bound)
                log.info("listening on \(bound, privacy: .public)")
                return
            } catch {
                log.error("start on port \(port, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                if port == 0 { state = .failed("\(error)") }
            }
        }
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
        let value = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "token",
        ]
        SecItemDelete(identity as CFDictionary)
        var add = identity
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        return value
    }
}
