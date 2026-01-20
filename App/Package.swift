// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CameramanApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../EngineKit")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["EngineKit"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
            path: "Tests/AppTests"
        ),
    ]
)
