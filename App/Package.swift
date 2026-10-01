// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameramanApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../EngineKit"),
        .package(path: "../MCPServer")
    ],
    targets: [
        .executableTarget(
            name: "Cameraman",
            dependencies: [
                "EngineKit",
                .product(name: "CameramanMCPCore", package: "MCPServer")
            ],
            path: "Sources/Cameraman"
        ),
        .testTarget(
            name: "CameramanTests",
            dependencies: ["Cameraman"],
            path: "Tests/CameramanTests"
        ),
    ]
)
