// swift-tools-version: 5.9
import PackageDescription

// Standalone MCP (Model Context Protocol) server for Project Studio.
// Reuses EngineKit (ProjectStore / ProjectLibrary / EditorModel) so the same
// non-destructive editing logic backs both the app and the MCP tools.
//
// Dependency-free by design: the MCP stdio transport is newline-delimited
// JSON-RPC 2.0, implemented directly in Foundation (mirrors EngineKit's
// zero-external-dependency ethos). macOS 13+ because it links EngineKit.
//
// Layered as a library (CameramanMCPCore) + a thin executable so the core is
// unit-testable without importing an @main entry point.
let package = Package(
    name: "CameramanMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../EngineKit")
    ],
    targets: [
        .target(
            name: "CameramanMCPCore",
            dependencies: ["EngineKit"],
            path: "Sources/CameramanMCPCore"
        ),
        .executableTarget(
            name: "cameraman-mcp",
            dependencies: ["CameramanMCPCore"],
            path: "Sources/cameraman-mcp"
        ),
        .testTarget(
            name: "CameramanMCPTests",
            dependencies: ["CameramanMCPCore"],
            path: "Tests/CameramanMCPTests"
        )
    ]
)
