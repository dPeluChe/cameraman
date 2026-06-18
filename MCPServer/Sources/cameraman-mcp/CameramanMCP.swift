//
//  CameramanMCP.swift
//  cameraman-mcp
//
//  Entry point. Runs an MCP server over stdio (newline-delimited JSON-RPC 2.0).
//  stdout is reserved for protocol messages; all logging goes to stderr.
//

import Foundation
import CameramanMCPCore

@main
struct CameramanMCP {
    static func main() async {
        FileHandle.standardError.write(Data("cameraman-mcp: starting (stdio)\n".utf8))
        let server = MCPServer()
        await server.run()
        FileHandle.standardError.write(Data("cameraman-mcp: stdin closed, exiting\n".utf8))
    }
}
